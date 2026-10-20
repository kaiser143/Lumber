import Foundation
import Observation

// MARK: - 全局状态

/// 数据来自真实的 pbxproj 解析；`--mock` 时退回内置演示数据。
@MainActor
@Observable
final class AppModel {
    var page: AppPage = .scan
    var phase: ScanPhase = .idle
    var projectName: String = ""
    var progress = ScanProgress()
    var items: [ResourceItem] = []
    var sessionIgnored: [ResourceItem] = []
    var selectedIDs: Set<UUID> = []
    /// 锁定到某个预览窗口的资源 id（预览窗口内左右键切换时使用，不影响主窗口选中）
    var previewItemID: UUID?
    var filter: ResourceType?
    var searchText: String = ""
    /// 只看「待确认」条目
    var reviewOnly = false
    var rules: [IgnoreRule] = IgnoreRule.builtIn    /// 扫描选项（设置页可调，仅本次运行有效，不持久化）
    var includeCodeFiles = true
    var scanDepth = 24
    var toast: String?
    var dropError: String?

    /// 当前解析出的工程（核心产物；mock 模式为 nil）
    var project: ProjectInfo?
    /// 本次扫描的全部候选资源（含被引用项），供 Statistics / 重新判定使用
    var inventory: [ResourceItem] = []
    /// 删除失败的条目 id（文件已不存在 / 系统拒绝），列表里标记「不可用」
    var unavailableIDs: Set<UUID> = []
    /// 等待二次确认的批量删除
    var pendingDeletion: [ResourceItem] = []
    var showingDeleteConfirm = false
    var isDeleting = false
    /// 是否使用内置演示数据（调试启动参数 --mock / --demo=xxx）
    private(set) var isMockMode = false

    var scanTask: Task<Void, Never>?

    init() {
        let arguments = CommandLine.arguments
        isMockMode = arguments.contains("--mock") || arguments.contains { $0.hasPrefix("--demo=") }
        loadPersistedRules()
        applyLaunchDemoIfNeeded()
        applyLaunchOpenIfNeeded(arguments)
    }

    /// 载入持久化的用户规则（内置规则始终存在）
    private func loadPersistedRules() {
        let userPatterns = IgnoreRulesStore.loadPatterns()
        rules = IgnoreRule.builtIn + userPatterns.map { IgnoreRule(pattern: $0) }
    }

    /// 供扫描引擎使用的编译后规则集
    var ignoreRuleSet: IgnoreRuleSet {
        IgnoreRuleSet(patterns: rules.map(\.pattern))
    }

    /// 扫描选项快照
    var scanOptions: ScanOptions {
        ScanOptions(includeCodeFiles: includeCodeFiles, maxDepth: scanDepth)
    }

    /// 把当前用户规则写回磁盘（内置规则不落盘）
    func persistUserRules() {
        let patterns = rules.filter { !$0.isBuiltIn }.map(\.pattern)
        IgnoreRulesStore.save(patterns)
    }

    /// 验收便利：`--open <工程路径>` 启动后直接扫描该工程
    private func applyLaunchOpenIfNeeded(_ arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--open"), index + 1 < arguments.count else { return }
        let path = (arguments[index + 1] as NSString).expandingTildeInPath
        openProject(at: URL(fileURLWithPath: path))
    }

    /// UI 回归入口：`--demo=results|scanning|rules|settings` 直接落到对应界面，
    /// 便于逐页验收（不读写磁盘，仅填充 Mock 数据）。
    private func applyLaunchDemoIfNeeded() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo=") }) else { return }
        let name = String(arg.dropFirst("--demo=".count))
        projectName = MockData.projectName
        switch name {
        case "results":
            items = MockData.projectItems
            selectedIDs = items.first.map { [$0.id] } ?? []
            progress = ScanProgress(fraction: 1, currentPath: "", scannedCount: 1_131, foundCount: items.count)
            phase = .results
        case "preview":
            items = MockData.projectItems
            if let first = items.first {
                selectedIDs = [first.id]
                previewItemID = first.id
            }
            progress = ScanProgress(fraction: 1, currentPath: "", scannedCount: 1_131, foundCount: items.count)
            phase = .results
        case "scanning":
            phase = .scanning
            progress = ScanProgress(
                fraction: 0.42,
                currentPath: "DemoApp/Assets.xcassets/banner.imageset/banner.png",
                scannedCount: 348,
                foundCount: 6
            )
        case "rules":
            page = .rules
        case "settings":
            page = .settings
        default:
            break
        }
    }

    var visibleItems: [ResourceItem] {
        items.filter { !sessionIgnored.map(\.id).contains($0.id) }
    }

    /// 分组下拉各分组的数量（待确认开关生效后也相应变化，搜索词不影响）
    var scopedItems: [ResourceItem] {
        reviewOnly ? visibleItems.filter(\.needsReview) : visibleItems
    }

    /// 当前分组（待确认开关 + 搜索后）里各类型的数量
    var scopedTypeCounts: [ResourceType: Int] {
        var counts: [ResourceType: Int] = [:]
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in scopedItems where keyword.isEmpty || item.name.localizedCaseInsensitiveContains(keyword) {
            counts[item.type, default: 0] += 1
        }
        return counts
    }

    var filteredItems: [ResourceItem] {
        var list = scopedItems
        if let filter { list = list.filter { $0.type == filter } }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
        }
        return list
    }

    var totalSizeText: String {
        let bytes = visibleItems.reduce(0) { $0 + $1.sizeBytes }
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
        return "\(max(1, Int((Double(bytes) / 1024).rounded()))) KB"
    }

    /// 高置信度未引用条目数（当前可见）
    var confirmedUnusedCount: Int { visibleItems.filter(\.isConfirmedUnused).count }

    /// 待确认条目数（当前可见）
    var needsReviewCount: Int { visibleItems.filter(\.needsReview).count }

    /// 顶部 TopHint 文案，贴近设计稿「默认 → Q3 · 均衡」的三段结构
    var topHintText: String {
        switch (page, phase) {
        case (.scan, .idle):
            return "默认 → Lumber · 冗余扫描"
        case (.scan, .scanning):
            return "默认 → \(projectTitle) · 扫描中"
        case (.scan, .results):
            return "默认 → \(projectTitle) · \(confirmedUnusedCount) 项未引用 · \(needsReviewCount) 待确认"
        case (.rules, _):
            return "默认 → 忽略规则 · .gitignore 语法"
        case (.settings, _):
            return "默认 → 设置 · 规则已持久化"
        }
    }

    /// 工程标题：真实工程用工程名，mock 用演示名
    var projectTitle: String {
        project?.name ?? projectName
    }

    /// 窗口标题：扫描后显示当前工程
    var windowTitle: String {
        project?.displayName ?? (projectName.isEmpty ? "Lumber" : projectName)
    }

    /// 待确认删除项的总大小
    var pendingDeletionSizeText: String {
        let bytes = pendingDeletion.reduce(0) { $0 + $1.sizeBytes }
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
        return "\(max(1, Int((Double(bytes) / 1024).rounded()))) KB"
    }

    // MARK: - 模拟扫描（--mock 模式，保留用于 UI 回归）

    /// 演示流程：不触碰磁盘，用 Task 模拟约 4 秒进度。
    func startMockScan(projectName: String = MockData.projectName) {
        resetScanState()
        project = nil
        self.projectName = projectName
        phase = .scanning

        let steps = MockData.scanSteps
        let result = MockData.projectItems
        scanTask = Task { @MainActor in
            let tick: UInt64 = 100_000_000 // 100ms
            for (index, step) in steps.enumerated() {
                try? await Task.sleep(nanoseconds: tick)
                if Task.isCancelled { return }
                let fraction = Double(index + 1) / Double(steps.count + 8) * 0.85
                progress = ScanProgress(
                    fraction: fraction,
                    currentPath: step,
                    scannedCount: (index + 1) * 87,
                    foundCount: min(result.count, index + 1)
                )
            }
            for extra in 0..<8 {
                try? await Task.sleep(nanoseconds: tick / 2)
                if Task.isCancelled { return }
                progress = ScanProgress(
                    fraction: 0.85 + Double(extra + 1) / 8 * 0.15,
                    currentPath: "汇总引用表…",
                    scannedCount: steps.count * 87 + extra * 13,
                    foundCount: result.count
                )
            }
            if Task.isCancelled { return }
            items = result
            selectedIDs = result.first.map { [$0.id] } ?? []
            phase = .results
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        progress = ScanProgress()
        project = nil
        inventory = []
    }

    func backToHome() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        projectName = ""
        progress = ScanProgress()
        project = nil
        inventory = []
        resetScanState()
    }

    /// 每次开始扫描前清空上一次的结果与选择
    func resetScanState() {
        page = .scan
        items = []
        sessionIgnored = []
        selectedIDs = []
        previewItemID = nil
        searchText = ""
        filter = nil
        reviewOnly = false
        unavailableIDs = []
        pendingDeletion = []
        showingDeleteConfirm = false
        progress = ScanProgress()
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == message { toast = nil }
        }
    }

    // MARK: - 拖放错误提示（不弹窗，4 秒后自动恢复）

    func presentDropError(_ message: String) {
        dropError = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if dropError == message { dropError = nil }
        }
    }

    func clearDropError() {
        dropError = nil
    }
}
