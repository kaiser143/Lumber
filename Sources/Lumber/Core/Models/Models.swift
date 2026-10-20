import Foundation

// MARK: - 资源类型

enum ResourceType: String, CaseIterable, Hashable, Codable {
    case image = "图片"
    case xib = "XIB·SB"
    case code = "代码"
    case other = "其他"

    var symbolName: String {
        switch self {
        case .image: return "photo"
        case .xib: return "doc.richtext"
        case .code: return "swift"
        case .other: return "doc"
        }
    }
}

// MARK: - 资源条目

/// 扫描引擎产出的资源条目。
/// Codable：预览窗口经 WindowGroup(value:) 打开，要求值可编码。
struct ResourceItem: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let relativePath: String
    /// 用于预览 / 缩略图 / Finder 定位的磁盘路径
    let absolutePath: String
    let sizeBytes: Int
    let type: ResourceType
    /// 是否进入「冗余」列表（包含待确认项）
    let unreferenced: Bool
    /// 低置信度：命中模糊信号（仅出现在注释、名称片段、未找到名称引用等），需人工确认
    let needsReview: Bool
    /// 判定说明，用于 tooltip 与预览页
    let note: String?
    /// 需要整体处理的目录（如 Assets.xcassets 里的 .imageset）；单文件资源为 nil
    let directoryPath: String?

    init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        absolutePath: String,
        sizeBytes: Int,
        type: ResourceType,
        unreferenced: Bool,
        needsReview: Bool = false,
        note: String? = nil,
        directoryPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.sizeBytes = sizeBytes
        self.type = type
        self.unreferenced = unreferenced
        self.needsReview = needsReview
        self.note = note
        self.directoryPath = directoryPath
    }

    var sizeText: String {
        if sizeBytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(sizeBytes) / 1_000_000)
        }
        return "\(max(1, Int((Double(sizeBytes) / 1024).rounded()))) KB"
    }

    /// 高置信度冗余（未引用且无需人工确认）
    var isConfirmedUnused: Bool { unreferenced && !needsReview }
}

// MARK: - 忽略规则

struct IgnoreRule: Identifiable, Hashable {
    let id: UUID
    var pattern: String
    var isBuiltIn: Bool

    init(pattern: String, isBuiltIn: Bool = false) {
        self.id = UUID()
        self.pattern = pattern
        self.isBuiltIn = isBuiltIn
    }

    static let builtIn: [IgnoreRule] = [
        IgnoreRule(pattern: "Pods/", isBuiltIn: true),
        IgnoreRule(pattern: "Carthage/", isBuiltIn: true),
        IgnoreRule(pattern: ".git/", isBuiltIn: true),
        IgnoreRule(pattern: "DerivedData/", isBuiltIn: true),
        IgnoreRule(pattern: "fastlane/", isBuiltIn: true),
        IgnoreRule(pattern: "*.xcworkspace/contents.xcworkspacedata", isBuiltIn: true),
    ]
}
