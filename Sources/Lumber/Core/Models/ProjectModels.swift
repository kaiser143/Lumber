import Foundation

// MARK: - 已解析的工程
//
// 解析 .xcodeproj 里登记的引用，形成引用表供冗余判定使用。
// 本结构不可变、可跨线程传递，扫描完成后回填到 AppModel。

struct ProjectInfo: Hashable {
    /// 被拖入/选择的 .xcodeproj 包路径
    let xcodeprojURL: URL
    /// 工程名，不含 .xcodeproj 后缀（如 DemoApp）
    let name: String
    /// 工程根目录（SOURCE_ROOT，即 .xcodeproj 所在目录 + projectDirPath）
    let rootDirectory: URL
    /// PBXNativeTarget 名称列表
    let targets: [String]
    /// pbxproj 中登记的文件绝对路径（已标准化，用于 O(1) 引用判定）
    let referencedPaths: Set<String>
    /// 整目录引用的路径（folder reference / Xcode 16 同步文件夹），其下所有文件视为被引用
    let folderReferencePaths: [String]
    /// 工程内的 Assets.xcassets 资源目录
    let assetCatalogs: [AssetCatalogInfo]
    /// Info.plist 中配置的 Main storyboard 名称（不含扩展名）
    let mainStoryboardName: String?
    /// 来自 Info.plist / 构建设置的资源名（storyboard、nib、AppIcon 等），这些名字永远视为已引用
    let referencedResourceNames: Set<String>
    /// pbxproj 里 PBXFileReference 的数量（仅用于界面汇总展示）
    let fileReferenceCount: Int
    /// 同一个 .xcworkspace 里被一并解析的其它工程（如 Pods.xcodeproj），仅用于界面 / 自检展示
    let linkedProjects: [String]

    /// 界面标题用：DemoApp.xcodeproj
    var displayName: String { xcodeprojURL.lastPathComponent }

    /// 该绝对路径是否被工程引用。
    /// 只要落在 folder reference / 同步文件夹里，整目录的内容都算被引用。
    func isReferenced(_ absolutePath: String) -> Bool {
        if referencedPaths.contains(absolutePath) { return true }
        for folder in folderReferencePaths where absolutePath.hasPrefix(folder + "/") {
            return true
        }
        return false
    }
}

// MARK: - Asset Catalog

struct AssetCatalogInfo: Hashable {
    /// Assets.xcassets 目录本身
    let url: URL
    /// 相对工程根目录的路径，如 App/Assets.xcassets
    let relativePath: String
    /// 目录下的 imageset / dataset / colorset 等条目
    let entries: [AssetEntry]

    var imageSetCount: Int { entries.filter { $0.kind == .imageSet }.count }
}

struct AssetEntry: Hashable {
    enum Kind: String {
        case imageSet = "imageset"
        case dataSet = "dataset"
        case colorSet = "colorset"
        case appIconSet = "appiconset"
        case symbolSet = "symbolset"
        case launchImage = "launchimage"
        case imageStack = "imagestack"
        case spriteAtlas = "spriteatlas"
        case brandAssets = "brandassets"
        case other = "other"

        /// 目录后缀，例如 .imageset
        var folderExtension: String { "." + rawValue }
    }

    /// 资源名（目录名去掉 .imageset 等后缀），代码里 imageNamed("name") 用的就是它
    let name: String
    let kind: Kind
    /// imageset 目录路径
    let url: URL
    /// 目录内实际包含的图片/数据文件名（来自 Contents.json 与实际文件）
    let fileNames: [String]
}

// MARK: - 解析错误

enum ProjectParseError: LocalizedError {
    case missingPBXProj(String)
    case unreadablePBXProj(String)
    case malformedPBXProj(String)

    var errorDescription: String? {
        switch self {
        case .missingPBXProj(let path):
            return "工程里找不到 project.pbxproj：\(path)"
        case .unreadablePBXProj(let reason):
            return "project.pbxproj 无法读取：\(reason)"
        case .malformedPBXProj(let reason):
            return "project.pbxproj 解析失败：\(reason)"
        }
    }
}

// MARK: - 拖放校验错误

enum ProjectDropError: LocalizedError {
    case unsupportedType(String)
    case emptyDirectory(String)
    case missingProject(String)
    case noReadPermission(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            return "「\(name)」不是 Xcode 工程，请拖入 .xcodeproj 或包含它的文件夹"
        case .emptyDirectory(let name):
            return "「\(name)」里没有找到 .xcodeproj 工程"
        case .missingProject(let name):
            return "找不到「\(name)」对应的 .xcodeproj"
        case .noReadPermission(let name):
            return "没有读取「\(name)」的权限。可在「系统设置 › 隐私与安全性 › 完全磁盘访问权限」中允许 Lumber"
        }
    }
}
