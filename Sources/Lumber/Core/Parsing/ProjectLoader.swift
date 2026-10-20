import Foundation

// MARK: - 工程装载
//
// 把「.xcodeproj 路径」变成一份 ProjectInfo：
// 1. 读取 project.pbxproj（UTF-8，兼容极少数 UTF-16 编码的旧工程）
// 2. 解析引用表（PBXProjectGraph）
// 3. 解析工程内所有 Assets.xcassets

enum ProjectLoader {
    static func load(xcodeprojURL: URL) throws -> ProjectInfo {
        let pbxprojURL = xcodeprojURL.appending(path: "project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw ProjectParseError.missingPBXProj(xcodeprojURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: pbxprojURL)
        } catch {
            throw ProjectParseError.unreadablePBXProj(error.localizedDescription)
        }
        guard let text = decode(data) else {
            throw ProjectParseError.unreadablePBXProj("文本编码无法识别")
        }

        let graph = try PBXProjectGraph.build(xcodeprojURL: xcodeprojURL, pbxprojText: text)
        // 同一个 workspace 里的其它工程（Pods.xcodeproj 等）也登记了同一批源文件，
        // 例如 CocoaPods 的 :path 本地 pod，其源码工程并不属于主 .xcodeproj。
        let linked = linkedProjectReferences(around: xcodeprojURL, excluding: xcodeprojURL)
        let catalogURLs = discoverAssetCatalogs(
            root: graph.rootDirectory,
            referenced: graph.assetCatalogURLs + linked.assetCatalogURLs
        )
        let catalogs = catalogURLs.map { url in
            AssetCatalogParser.parse(catalogURL: url, relativePath: relativePath(of: url, in: graph.rootDirectory))
        }

        let plistNames = plistResourceNames(in: graph.infoPlistPaths)
        return ProjectInfo(
            xcodeprojURL: xcodeprojURL,
            name: graph.projectName,
            rootDirectory: graph.rootDirectory,
            targets: graph.targets,
            referencedPaths: graph.referencedPaths.union(linked.referencedPaths),
            folderReferencePaths: graph.folderReferencePaths + linked.folderReferencePaths,
            assetCatalogs: catalogs,
            mainStoryboardName: graph.mainStoryboardName ?? mainStoryboard(in: graph.infoPlistPaths),
            referencedResourceNames: graph.buildSettingResourceNames.union(plistNames).union(linked.resourceNames),
            fileReferenceCount: graph.fileReferenceCount + linked.fileReferenceCount,
            linkedProjects: linked.projectNames
        )
    }

    // MARK: - workspace 里的兄弟工程

    private struct LinkedReferences {
        var referencedPaths: Set<String> = []
        var folderReferencePaths: [String] = []
        var assetCatalogURLs: [URL] = []
        var resourceNames: Set<String> = []
        var fileReferenceCount: Int = 0
        var projectNames: [String] = []
    }

    private static func linkedProjectReferences(around xcodeprojURL: URL, excluding mainURL: URL) -> LinkedReferences {
        var result = LinkedReferences()
        let main = mainURL.standardizedFileURL.path
        for projectURL in workspaceProjectURLs(near: xcodeprojURL) {
            guard projectURL.standardizedFileURL.path != main else { continue }
            let pbxURL = projectURL.appending(path: "project.pbxproj")
            guard let data = FileManager.default.contents(atPath: pbxURL.path),
                  let text = decode(data),
                  let graph = try? PBXProjectGraph.build(xcodeprojURL: projectURL, pbxprojText: text) else { continue }
            result.referencedPaths.formUnion(graph.referencedPaths)
            result.folderReferencePaths.append(contentsOf: graph.folderReferencePaths)
            result.assetCatalogURLs.append(contentsOf: graph.assetCatalogURLs)
            result.resourceNames.formUnion(graph.buildSettingResourceNames)
            result.fileReferenceCount += graph.fileReferenceCount
            result.projectNames.append(graph.projectName)
        }
        return result
    }

    /// 与主工程同名的 .xcworkspace 优先；没有再退回目录里第一个 .xcworkspace
    private static func workspaceProjectURLs(near xcodeprojURL: URL) -> [URL] {
        let directory = xcodeprojURL.deletingLastPathComponent()
        let preferred = directory.appending(
            path: xcodeprojURL.deletingPathExtension().lastPathComponent + ".xcworkspace"
        )
        let workspace: URL
        if FileManager.default.fileExists(atPath: preferred.appending(path: "contents.xcworkspacedata").path) {
            workspace = preferred
        } else {
            let candidates = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            guard let first = candidates
                .filter({ $0.pathExtension == "xcworkspace" })
                .filter({ FileManager.default.fileExists(atPath: $0.appending(path: "contents.xcworkspacedata").path) })
                .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
                .first else { return [] }
            workspace = first
        }

        let dataURL = workspace.appending(path: "contents.xcworkspacedata")
        guard let data = FileManager.default.contents(atPath: dataURL.path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return projectURLs(inWorkspaceText: text, base: workspace.deletingLastPathComponent())
    }

    private static func projectURLs(inWorkspaceText text: String, base directory: URL) -> [URL] {
        let pattern = #"location\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        var urls: [URL] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let location = nsText.substring(with: match.range(at: 1))
            let raw: String
            if location.hasPrefix("group:") {
                raw = String(location.dropFirst("group:".count))
            } else if location.hasPrefix("container:") {
                raw = String(location.dropFirst("container:".count))
            } else {
                continue
            }
            let url = raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw)
                : directory.appending(path: raw)
            let standardized = url.standardizedFileURL
            if standardized.pathExtension == "xcodeproj" { urls.append(standardized) }
        }
        return urls
    }

    /// 从 INFOPLIST_FILE 指向的 Info.plist 里读取 Main storyboard 名称
    private static func mainStoryboard(in infoPlistPaths: [String]) -> String? {
        for path in infoPlistPaths {
            guard let plist = readPlist(at: path) else { continue }
            guard var name = (plist["UIMainStoryboardFile"] as? String)
                ?? (plist["NSMainStoryboardFile"] as? String),
                  !name.isEmpty else { continue }
            if name.hasSuffix(".storyboard") { name = String(name.dropLast(".storyboard".count)) }
            return name
        }
        return nil
    }

    /// Info.plist 里声明的主/启动 storyboard、nib 名称：这些文件名不会出现在代码里，但确实被使用
    private static func plistResourceNames(in infoPlistPaths: [String]) -> Set<String> {
        let keys = [
            "UIMainStoryboardFile", "UIMainStoryboardFile~ipad",
            "NSMainStoryboardFile",
            "UILaunchStoryboardName", "UILaunchStoryboardName~ipad",
            "NSMainNibFile", "NSMainNibFile~ipad",
        ]
        var names: Set<String> = []
        for path in infoPlistPaths {
            guard let plist = readPlist(at: path) else { continue }
            for key in keys {
                guard var name = plist[key] as? String, !name.isEmpty else { continue }
                for suffix in [".storyboard", ".xib"] where name.hasSuffix(suffix) {
                    name = String(name.dropLast(suffix.count))
                }
                names.insert(name)
            }
            for name in (plist["UILaunchStoryboardNames"] as? [String]) ?? [] where !name.isEmpty {
                names.insert(name)
            }
        }
        return names
    }

    private static func readPlist(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            return nil
        }
        return plist
    }

    private static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    /// pbxproj 里登记的 .xcassets + 磁盘上实际存在但未登记的 .xcassets（后者会显得「未被引用」）
    private static func discoverAssetCatalogs(root: URL, referenced: [URL]) -> [URL] {
        var catalogs: [URL] = referenced.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }

        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") || Self.skippedDirectories.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                if name.hasSuffix(".xcassets") {
                    enumerator.skipDescendants()
                    if !catalogs.contains(url) { catalogs.append(url) }
                }
            }
        }
        return catalogs.map(\.standardizedFileURL)
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    static let skippedDirectories: Set<String> = [
        "Pods", "Carthage", "DerivedData", "build", ".build", "node_modules", "fastlane",
    ]

    static func relativePath(_ url: URL, in root: URL) -> String {
        relativePath(of: url, in: root)
    }
}
