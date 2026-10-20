import Foundation
import UniformTypeIdentifiers

// MARK: - 工程拖放、解析与扫描
//
// 状态仍集中在 AppModel，这里只放「与磁盘打交道」的流程：
// 拖放 → 校验 → 解析 pbxproj → 后台扫描清单 → 回填结果。

extension AppModel {
    /// 拖入的 NSItemProvider → 文件 URL → 校验 → 扫描
    func acceptDrop(providers: [NSItemProvider]) async {
        clearDropError()
        guard let url = await Self.firstDroppedURL(from: providers) else {
            presentDropError("没能读取拖入的内容，请拖入 .xcodeproj 或包含它的文件夹")
            return
        }
        openProject(at: url)
    }

    /// 点击拖放区：走系统选择面板
    func chooseProject() {
        clearDropError()
        guard let url = ProjectPicker.chooseProject() else { return }
        openProject(at: url)
    }

    /// 校验并进入扫描；--mock 调试模式下走演示流程
    func openProject(at url: URL) {
        do {
            let xcodeprojURL = try ProjectResolver.resolve(url)
            if isMockMode {
                startMockScan(projectName: xcodeprojURL.lastPathComponent)
            } else {
                startScan(xcodeprojURL: xcodeprojURL)
            }
        } catch {
            presentDropError(error.localizedDescription)
        }
    }

    /// 真实扫描：pbxproj 解析 + 冗余判定引擎，全部在后台执行
    func startScan(xcodeprojURL: URL) {
        scanTask?.cancel()
        resetScanState()
        project = nil
        inventory = []
        projectName = xcodeprojURL.lastPathComponent
        phase = .scanning
        progress = ScanProgress(fraction: 0.01, phaseText: "解析工程", currentPath: "读取 project.pbxproj…")

        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let info = try await Task.detached(priority: .userInitiated) {
                    try ProjectLoader.load(xcodeprojURL: xcodeprojURL)
                }.value
                if Task.isCancelled { return }

                self.project = info
                self.projectName = info.name
                var parsedText = "\(info.displayName) · \(info.targets.count) 个 target · \(info.assetCatalogs.count) 个资源目录"
                if !info.linkedProjects.isEmpty {
                    parsedText += " · 同时读取 \(info.linkedProjects.joined(separator: "、"))"
                }
                self.progress = ScanProgress(
                    fraction: 0.04,
                    phaseText: "工程解析完成",
                    currentPath: parsedText
                )

                let outcome = await ScanEngine().scan(
                    project: info,
                    rules: self.ignoreRuleSet,
                    options: self.scanOptions
                ) { [weak self] update in
                    guard let self else { return }
                    self.progress = ScanProgress(
                        fraction: update.fraction,
                        phaseText: update.phaseText,
                        currentPath: update.currentPath,
                        scannedCount: update.scannedCount,
                        totalCount: update.totalCount,
                        foundCount: update.foundCount,
                        uncertainCount: update.uncertainCount,
                        ignoredCount: update.ignoredCount,
                        typeCounts: update.typeCounts
                    )
                }
                if Task.isCancelled { return }

                let listed = outcome.listedItems
                self.inventory = outcome.items
                self.items = listed
                self.selectedIDs = listed.first.map { [$0.id] } ?? []
                self.phase = .results
                self.showToast(Self.summaryText(for: outcome))
            } catch {
                if Task.isCancelled { return }
                self.phase = .idle
                self.projectName = ""
                self.project = nil
                self.progress = ScanProgress()
                self.presentDropError(error.localizedDescription)
            }
        }
    }

    private static func summaryText(for outcome: ScanOutcome) -> String {
        let listed = outcome.listedItems.count
        guard listed > 0 else {
            return "扫描完成：\(outcome.items.count) 个候选资源，没有发现未引用项"
        }
        let confirmed = outcome.confirmedCount
        let uncertain = outcome.uncertainCount
        let seconds = String(format: "%.1fs", outcome.seconds)
        return "扫描完成（\(seconds)）：\(confirmed) 项未引用，\(uncertain) 项待确认"
    }

    /// 结果页「重新扫描」
    func rescan() {
        if let project {
            startScan(xcodeprojURL: project.xcodeprojURL)
        } else if isMockMode {
            startMockScan(projectName: projectName)
        }
    }

    // MARK: - NSItemProvider → URL

    private static func firstDroppedURL(from providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if let url = await droppedURL(from: provider) { return url }
        }
        return nil
    }

    private static func droppedURL(from provider: NSItemProvider) async -> URL? {
        let typeIdentifier = UTType.fileURL.identifier
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                } else if let string = item as? String {
                    resolved = URL(string: string)
                }
                continuation.resume(returning: resolved)
            }
        }
    }
}
