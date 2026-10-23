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
    /// 单例预览窗口当前展示的资源 id（左右键切换时更新，不影响主窗口选中）
    var previewItemID: UUID?
    var filter: ResourceType?
    var searchText: String = ""
    /// 按判定状态筛选（高置信度 / 待确认 / 未加入 target）
    var statusFilter: StatusFilter = .all
    /// 结果列表排序方式（本次运行有效）
    var sortOption: SortOption = .standard
    /// 当前键盘焦点所在条目（用于方向键滚动到可视区）
    var activeSelectionID: UUID?
    /// 搜索框提交后请求把焦点还给列表
    var listFocusRequest = 0
    /// 方向键切换选中后请求把条目滚进可视区（删除/点击等不要触发）
    var selectionScrollRequest = 0
    /// ⌘F / 菜单请求把焦点交给搜索框
    var searchFocusRequest = 0
    var rules: [IgnoreRule] = IgnoreRule.builtIn
    /// 扫描选项（设置页可调，持久化到 Application Support）
    var includeCodeFiles = true {
        didSet { persistPreferencesIfNeeded(oldValue: oldValue, newValue: includeCodeFiles) }
    }
    var scanDepth = 24 {
        didSet { persistPreferencesIfNeeded(oldValue: oldValue, newValue: scanDepth) }
    }
    /// 移到废纸篓后同步清理 project.pbxproj 引用
    var cleanPbxprojOnDelete = true {
        didSet { persistPreferencesIfNeeded(oldValue: oldValue, newValue: cleanPbxprojOnDelete) }
    }
    var toast: String?
    var dropError: String?

    /// 当前解析出的工程（核心产物；mock 模式为 nil）
    var project: ProjectInfo?
    /// 拖入目录 / workspace 里发现多个工程时，等待用户选择
    var pendingProjects: [URL] = []
    var showingProjectChoice = false
    /// 删除失败的条目 id（文件已不存在 / 系统拒绝），列表里标记「不可用」
    var unavailableIDs: Set<UUID> = []
    /// 等待二次确认的批量删除
    var pendingDeletion: [ResourceItem] = []
    var showingDeleteConfirm = false
    var isDeleting = false
    /// 首页「最近工程」
    var recentProjects: [RecentProject] = []
    /// 是否使用内置演示数据（调试启动参数 --mock / --demo=xxx）
    private(set) var isMockMode = false
    /// 避免 init 加载偏好时触发 didSet 再写盘
    private var isLoadingPreferences = false

    var scanTask: Task<Void, Never>?

    init() {
        let arguments = CommandLine.arguments
        isMockMode = arguments.contains("--mock") || arguments.contains { $0.hasPrefix("--demo=") }
        loadPersistedRules()
        loadPersistedPreferences()
        recentProjects = PreferencesStore.loadRecentProjects()
        applyLaunchDemoIfNeeded()
        applyLaunchOpenIfNeeded(arguments)
    }

    /// 载入持久化的用户规则（内置规则始终存在）
    private func loadPersistedRules() {
        let userPatterns = IgnoreRulesStore.loadPatterns()
        rules = IgnoreRule.builtIn + userPatterns.map { IgnoreRule(pattern: $0) }
    }

    private func loadPersistedPreferences() {
        isLoadingPreferences = true
        let prefs = PreferencesStore.loadPreferences()
        includeCodeFiles = prefs.includeCodeFiles
        scanDepth = prefs.scanDepth
        cleanPbxprojOnDelete = prefs.cleanPbxprojOnDelete
        isLoadingPreferences = false
    }

    private func persistPreferencesIfNeeded<T: Equatable>(oldValue: T, newValue: T) {
        guard !isLoadingPreferences, oldValue != newValue else { return }
        PreferencesStore.savePreferences(AppPreferences(
            includeCodeFiles: includeCodeFiles,
            scanDepth: scanDepth,
            cleanPbxprojOnDelete: cleanPbxprojOnDelete
        ))
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

    func openRecentProject(_ recent: RecentProject) {
        guard recent.exists else {
            recentProjects = PreferencesStore.removeRecentProject(path: recent.path)
            showToast("「\(recent.displayName)」已不存在，已从最近列表移除")
            return
        }
        openProject(at: recent.url)
    }

    func removeRecentProject(_ recent: RecentProject) {
        recentProjects = PreferencesStore.removeRecentProject(path: recent.path)
    }

    func clearRecentProjects() {
        PreferencesStore.clearRecentProjects()
        recentProjects = []
    }

    /// 验收便利：`--open <工程路径>` 启动后直接扫描该工程
    private func applyLaunchOpenIfNeeded(_ arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--open"), index + 1 < arguments.count else { return }
        let path = (arguments[index + 1] as NSString).expandingTildeInPath
        openProject(at: URL(fileURLWithPath: path))
    }

    /// UI 回归入口：`--demo=results|scanning|rules|settings|about` 直接落到对应界面，
    /// 便于逐页验收（不读写磁盘，仅填充 Mock 数据）。
    private func applyLaunchDemoIfNeeded() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo=") }) else { return }
        let name = String(arg.dropFirst("--demo=".count))
        projectName = MockData.projectName
        switch name {
        case "results":
            items = MockData.projectItems
            selectedIDs = items.first.map { [$0.id] } ?? []
            activeSelectionID = items.first?.id
            progress = ScanProgress(fraction: 1, currentPath: "", scannedCount: 1_131, foundCount: items.count)
            phase = .results
        case "preview":
            items = MockData.projectItems
            if let first = items.first {
                selectedIDs = [first.id]
                activeSelectionID = first.id
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
        case "about":
            page = .about
        default:
            break
        }
    }

    var visibleItems: [ResourceItem] {
        guard !sessionIgnored.isEmpty else { return items }
        let ignoredIDs = Set(sessionIgnored.map(\.id))
        return items.filter { !ignoredIDs.contains($0.id) }
    }

    /// 分组下拉各分组的数量（状态筛选生效后也相应变化，搜索词不影响）
    var scopedItems: [ResourceItem] {
        statusFilter == .all ? visibleItems : visibleItems.filter(statusFilter.matches)
    }

    /// 当前分组（待确认开关 + 搜索后）里各类型的数量
    var scopedTypeCounts: [ResourceType: Int] {
        var counts: [ResourceType: Int] = [:]
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in scopedItems where keyword.isEmpty
            || item.name.localizedCaseInsensitiveContains(keyword)
            || item.relativePath.localizedCaseInsensitiveContains(keyword) {
            counts[item.type, default: 0] += 1
        }
        return counts
    }

    var filteredItems: [ResourceItem] {
        var list = scopedItems
        if let filter { list = list.filter { $0.type == filter } }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(keyword)
                    || $0.relativePath.localizedCaseInsensitiveContains(keyword)
            }
        }
        switch sortOption {
        case .standard:
            break
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            list.sort { $0.sizeBytes > $1.sizeBytes }
        case .type:
            list.sort {
                if $0.type != $1.type { return $0.type.rawValue < $1.type.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .path:
            list.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }
        return list
    }

    /// 当前筛选结果的条目总大小（含待确认项）
    var totalSizeText: String {
        SizeFormat.text(filteredItems.reduce(0) { $0 + $1.sizeBytes })
    }

    /// 当前筛选结果里高置信度未引用的总大小（不含待确认 / 未加入 target）
    var reclaimableSizeText: String {
        SizeFormat.text(filteredItems.filter(\.isConfirmedUnused).reduce(0) { $0 + $1.sizeBytes })
    }

    /// 高置信度未引用条目数（当前可见）
    var confirmedUnusedCount: Int { visibleItems.filter(\.isConfirmedUnused).count }

    /// 待确认条目数（当前可见）
    var needsReviewCount: Int { visibleItems.filter(\.needsReview).count }

    /// 未加入 target 条目数（当前可见）
    var notInTargetCount: Int { visibleItems.filter(\.notInTarget).count }

    /// 状态筛选菜单里各档的数量
    func statusFilterCount(for filter: StatusFilter) -> Int {
        switch filter {
        case .all: return visibleItems.count
        case .confirmed: return confirmedUnusedCount
        case .needsReview: return needsReviewCount
        case .notInTarget: return notInTargetCount
        }
    }

    /// 导航栏顶部文案
    var topHintText: String {
        switch (page, phase) {
        case (.scan, .idle):
            return "Lumber · 冗余扫描"
        case (.scan, .scanning):
            return "\(projectTitle) · 扫描中"
        case (.scan, .results):
            return "\(projectTitle) · \(confirmedUnusedCount) 未引用 · \(needsReviewCount) 待确认 · \(totalSizeText)（可释放 \(reclaimableSizeText)）"
        case (.rules, _):
            return "忽略规则 · .gitignore 语法"
        case (.settings, _):
            return "设置 · 选项与规则已持久化"
        case (.about, _):
            return "关于 Lumber · 本地解析 · 零依赖"
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
        SizeFormat.text(pendingDeletion.reduce(0) { $0 + $1.sizeBytes })
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
            activeSelectionID = result.first?.id
            phase = .results
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        progress = ScanProgress()
        project = nil
    }

    func backToHome() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        projectName = ""
        progress = ScanProgress()
        project = nil
        resetScanState()
    }

    /// 每次开始扫描前清空上一次的结果与选择
    func resetScanState() {
        page = .scan
        items = []
        sessionIgnored = []
        selectedIDs = []
        activeSelectionID = nil
        previewItemID = nil
        searchText = ""
        filter = nil
        statusFilter = .all
        unavailableIDs = []
        pendingDeletion = []
        showingDeleteConfirm = false
        pendingProjects = []
        showingProjectChoice = false
        progress = ScanProgress()
    }

    // MARK: - Toast
    //
    // 用递增 token 而不是比较文案：连续两次相同提示时，前一个延时任务不会提前清掉后一个。

    private var toastToken = 0

    func showToast(_ message: String) {
        toastToken += 1
        let token = toastToken
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastToken == token { toast = nil }
        }
    }

    // MARK: - 拖放错误提示（不弹窗，4 秒后自动恢复）

    private var dropErrorToken = 0

    func presentDropError(_ message: String) {
        dropErrorToken += 1
        let token = dropErrorToken
        dropError = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if dropErrorToken == token { dropError = nil }
        }
    }

    func clearDropError() {
        dropError = nil
    }

    func requestListFocus() {
        listFocusRequest += 1
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }
}
