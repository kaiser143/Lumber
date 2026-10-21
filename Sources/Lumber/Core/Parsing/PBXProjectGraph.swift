import Foundation

// MARK: - pbxproj 语义解析
//
// 从字典树里提炼出「工程引用表」：
// · referencedPaths        被 pbxproj 引用的文件绝对路径
// · builtPaths             出现在 PBXBuildFile 里、真正参与 target 构建的路径
// · folderReferencePaths   整目录引用（folder reference / Xcode 16 同步文件夹）
// · targets / 主 storyboard / Assets.xcassets 位置
//
// 已知边界与假设（不静默简化）：
// 1. PBXVariantGroup 的 path 只是虚拟名（如 InfoPlist.strings），
//    子项真实路径相对「variant group 的上一级目录」，因此拼接时跳过它。
// 2. sourceTree 为 BUILT_PRODUCTS_DIR / SDKROOT / DEVELOPER_DIR 的引用不在源码树内，
//    直接忽略（它们不是用户磁盘上的资源）。
// 3. PBXFileSystemSynchronizedRootGroup（Xcode 16 同步文件夹）按「整目录被引用 + 自动加入 target」处理，
//    其 exceptions 不做进一步区分。
// 4. 只读取第一个 rootObject，嵌套工程（子工程 .xcodeproj）不递归解析。

struct PBXProjectGraph {
    let xcodeprojURL: URL
    let projectName: String
    let rootDirectory: URL
    let targets: [String]
    let referencedPaths: Set<String>
    /// 出现在 PBXBuildFile 里、真正参与 target 构建的路径（含 folder reference / variant group 子项）
    let builtPaths: Set<String>
    let folderReferencePaths: [String]
    /// Xcode 16 同步根组（由 Xcode 自动加入 target）
    let synchronizedRootPaths: [String]
    let assetCatalogURLs: [URL]
    let mainStoryboardName: String?
    /// 构建配置里声明的资源名（Infoplist 键、AppIcon 名等），这些名字必须视为被引用
    let buildSettingResourceNames: Set<String>
    let fileReferenceCount: Int
    /// 构建配置里的 INFOPLIST_FILE（绝对路径），用于解析 Main storyboard
    let infoPlistPaths: [String]
}

extension PBXProjectGraph {
    static func build(xcodeprojURL: URL, pbxprojText: String) throws -> PBXProjectGraph {
        let root = try PBXParser.parse(pbxprojText)
        guard let objects = root.dictionary("objects") else {
            throw ProjectParseError.malformedPBXProj("缺少 objects 节点")
        }
        let projectName = xcodeprojURL.deletingPathExtension().lastPathComponent
        let rootObjectID = root.string("rootObject")
        let projectObject = rootObjectID.flatMap { objects[$0]?.dictionaryValue }

        var rootDirectory = xcodeprojURL.deletingLastPathComponent()
        if let dirPath = projectObject?.string("projectDirPath"), !dirPath.isEmpty {
            rootDirectory = rootDirectory.appending(path: dirPath)
        }
        rootDirectory = rootDirectory.standardizedFileURL

        let resolver = PathResolver(objects: objects, rootDirectory: rootDirectory)

        var referencedPaths: Set<String> = []
        var folderReferencePaths: [String] = []
        var synchronizedRootPaths: [String] = []
        var assetCatalogURLs: [URL] = []
        var fileReferenceCount = 0

        for (id, value) in objects {
            guard let dict = value.dictionaryValue, let isa = dict.string("isa") else { continue }
            switch isa {
            case "PBXFileReference":
                fileReferenceCount += 1
                guard let path = resolver.resolve(id) else { continue }
                referencedPaths.insert(path)
                let fileType = dict.string("lastKnownFileType") ?? ""
                // folder reference（蓝色文件夹）与 .xcassets 资源目录都是「整目录引用」：
                // 目录内文件不单独出现在 pbxproj 里，但都属于工程资源。
                if fileType == "folder" || path.hasSuffix(".xcassets") {
                    folderReferencePaths.append(path)
                }
                if path.hasSuffix(".xcassets") {
                    assetCatalogURLs.append(URL(fileURLWithPath: path, isDirectory: true))
                }
            case "PBXFileSystemSynchronizedRootGroup":
                guard let path = resolver.resolve(id) else { continue }
                referencedPaths.insert(path)
                folderReferencePaths.append(path)
                synchronizedRootPaths.append(path)
            default:
                continue
            }
        }

        return PBXProjectGraph(
            xcodeprojURL: xcodeprojURL,
            projectName: projectName,
            rootDirectory: rootDirectory,
            targets: targetNames(objects: objects, projectObject: projectObject),
            referencedPaths: referencedPaths,
            builtPaths: builtFilePaths(objects: objects, resolver: resolver),
            folderReferencePaths: folderReferencePaths,
            synchronizedRootPaths: synchronizedRootPaths,
            assetCatalogURLs: assetCatalogURLs,
            mainStoryboardName: mainStoryboardName(objects: objects),
            buildSettingResourceNames: buildSettingResourceNames(objects: objects),
            fileReferenceCount: fileReferenceCount,
            infoPlistPaths: infoPlistPaths(objects: objects, rootDirectory: rootDirectory)
        )
    }

    /// PBXBuildFile.fileRef → 已解析的绝对路径。
    /// VariantGroup / XCVersionGroup 本身是虚拟节点，需要展开到 children 才拿得到真实文件。
    private static func builtFilePaths(
        objects: [String: PBXValue],
        resolver: PathResolver
    ) -> Set<String> {
        var paths: Set<String> = []
        for value in objects.values {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "PBXBuildFile",
                  let fileRef = dict.string("fileRef") else { continue }

            if let ref = objects[fileRef]?.dictionaryValue {
                let isa = ref.string("isa") ?? ""
                if isa == "PBXVariantGroup" || isa == "XCVersionGroup",
                   let children = ref["children"]?.arrayValue {
                    for child in children {
                        guard let id = child.stringValue,
                              let path = resolver.resolve(id) else { continue }
                        paths.insert(path)
                    }
                    continue
                }
                // fileRef 只应指向文件 / VariantGroup；指向 Group 属于损坏的 pbxproj，跳过避免把根目录当文件
                guard isa == "PBXFileReference" else { continue }
            } else {
                continue
            }
            if let path = resolver.resolve(fileRef) {
                paths.insert(path)
            }
        }
        return paths
    }

    private static func infoPlistPaths(
        objects: [String: PBXValue],
        rootDirectory: URL
    ) -> [String] {
        var paths: Set<String> = []
        for value in objects.values {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "XCBuildConfiguration",
                  let settings = dict.dictionary("buildSettings"),
                  let raw = settings.string("INFOPLIST_FILE"), !raw.isEmpty,
                  !raw.hasPrefix("$(") else { continue }
            let url = raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw)
                : rootDirectory.appending(path: raw)
            paths.insert(url.standardizedFileURL.path)
        }
        return Array(paths)
    }

    private static func targetNames(
        objects: [String: PBXValue],
        projectObject: [String: PBXValue]?
    ) -> [String] {
        var names: [String] = []
        if let targetIDs = projectObject?["targets"]?.arrayValue {
            for case let idValue in targetIDs {
                guard let id = idValue.stringValue,
                      let dict = objects[id]?.dictionaryValue,
                      let name = dict.string("name") else { continue }
                names.append(name)
            }
        }
        if names.isEmpty {
            names = objects.values.compactMap { value in
                let dict = value.dictionaryValue
                guard dict?.string("isa") == "PBXNativeTarget" else { return nil }
                return dict?.string("name")
            }
            names.sort()
        }
        return names
    }

    private static func mainStoryboardName(objects: [String: PBXValue]) -> String? {
        let keys = ["INFOPLIST_KEY_UIMainStoryboardFile", "INFOPLIST_KEY_NSMainStoryboardFile"]
        for value in objects.values {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "XCBuildConfiguration",
                  let settings = dict.dictionary("buildSettings") else { continue }
            for key in keys {
                guard var name = settings.string(key), !name.isEmpty else { continue }
                if name.hasSuffix(".storyboard") { name = String(name.dropLast(".storyboard".count)) }
                if !name.hasPrefix("$(") { return name }
            }
        }
        return nil
    }

    /// 构建设置里直接写死的资源名：主/启动 storyboard、nib、AppIcon 等
    private static func buildSettingResourceNames(objects: [String: PBXValue]) -> Set<String> {
        let keys = [
            "INFOPLIST_KEY_UIMainStoryboardFile",
            "INFOPLIST_KEY_NSMainStoryboardFile",
            "INFOPLIST_KEY_UILaunchStoryboardName",
            "INFOPLIST_KEY_NSMainNibFile",
            "ASSETCATALOG_COMPILER_APPICON_NAME",
            "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME",
        ]
        var names: Set<String> = []
        for value in objects.values {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "XCBuildConfiguration",
                  let settings = dict.dictionary("buildSettings") else { continue }
            for key in keys {
                guard var name = settings.string(key), !name.isEmpty, !name.hasPrefix("$(") else { continue }
                name = name.replacingOccurrences(of: "\"", with: "")
                for suffix in [".storyboard", ".xib"] where name.hasSuffix(suffix) {
                    name = String(name.dropLast(suffix.count))
                }
                names.insert(name)
            }
        }
        return names
    }
}

// MARK: - 路径解析
//
// 沿 PBXGroup 父链把相对路径拼成绝对路径。
// 父链通过「所有对象的 children 数组」反推得到。

private struct PathResolver {
    let objects: [String: PBXValue]
    let rootDirectory: URL
    private let parentOf: [String: String]

    init(objects: [String: PBXValue], rootDirectory: URL) {
        self.objects = objects
        self.rootDirectory = rootDirectory
        var parents: [String: String] = [:]
        for (id, value) in objects {
            guard let dict = value.dictionaryValue,
                  let children = dict["children"]?.arrayValue else { continue }
            for child in children {
                if let childID = child.stringValue { parents[childID] = id }
            }
        }
        self.parentOf = parents
    }

    func resolve(_ id: String) -> String? {
        guard objects[id] != nil else { return nil }
        var components: [String] = []
        var base: URL?
        var currentID: String? = id
        var visited: Set<String> = []

        while let current = currentID, visited.insert(current).inserted {
            guard let dict = objects[current]?.dictionaryValue else { break }
            let isa = dict.string("isa") ?? ""
            let sourceTree = dict.string("sourceTree") ?? "<group>"
            let isVirtualContainer = (isa == "PBXVariantGroup" || isa == "XCVersionGroup")

            if let path = dict.string("path"), !path.isEmpty, !isVirtualContainer {
                // 含构建变量（$(SRCROOT) 等）或 ~ 的路径无法在解析阶段求值，直接放弃
                if path.contains("$(") || path.hasPrefix("~") { return nil }
                if path.hasPrefix("/") {
                    base = URL(fileURLWithPath: path, isDirectory: true)
                    currentID = nil
                    break
                }
                components.insert(path, at: 0)
            }

            switch sourceTree {
            case "<group>":
                currentID = parentOf[current]
            case "SOURCE_ROOT", "SRCROOT", "PROJECT_DIR", "<absolute>":
                base = rootDirectory
                currentID = nil
            default:
                // BUILT_PRODUCTS_DIR / SDKROOT / DEVELOPER_DIR：不在源码树内
                return nil
            }
        }

        var url = base ?? rootDirectory
        if !components.isEmpty {
            url = url.appending(path: components.joined(separator: "/"))
        }
        return url.standardizedFileURL.path
    }
}
