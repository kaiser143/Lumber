import Foundation

// MARK: - 页面与阶段

/// 主流程阶段：空闲（首页）→ 扫描中 → 结果列表
enum ScanPhase {
    case idle
    case scanning
    case results
}

/// 边栏可达页面：扫描流程、忽略规则、设置、关于
enum AppPage: Hashable {
    case scan
    case rules
    case settings
    case about
}

// MARK: - 结果排序

enum SortOption: String, CaseIterable, Identifiable, Hashable {
    case standard = "默认"
    case name = "名称"
    case size = "大小"
    case type = "类型"
    case path = "路径"

    var id: String { rawValue }
}

// MARK: - 扫描进度

/// 扫描过程中回填到界面的进度快照
struct ScanProgress {
    var fraction: Double = 0
    /// 当前阶段文案（统计文件 / 遍历索引 / 判定冗余 / 汇总）
    var phaseText: String = ""
    var currentPath: String = ""
    var scannedCount: Int = 0
    var totalCount: Int = 0
    var foundCount: Int = 0
    var uncertainCount: Int = 0
    /// 命中忽略规则而跳过的文件/目录数
    var ignoredCount: Int = 0
    /// 已发现的冗余条目按类型计数
    var typeCounts: [ResourceType: Int] = [:]

    /// 兜底：演示流程没有阶段文案时显示「扫描中」
    var phaseDisplayText: String { phaseText.isEmpty ? "扫描中" : phaseText }
}
