import Foundation

// MARK: - 列表操作：忽略 / 删除（废纸篓）/ 规则增删

extension AppModel {
    func ignore(_ item: ResourceItem) {
        ignore([item])
    }

    /// 忽略若干条目（右键单条或多选）；已忽略的会跳过
    func ignore(_ targets: [ResourceItem]) {
        let fresh = targets.filter { item in
            !sessionIgnored.contains(where: { $0.id == item.id })
        }
        guard !fresh.isEmpty else { return }
        let ids = Set(fresh.map(\.id))
        let nextSelection = nextActiveSelectionID(removing: ids)
        sessionIgnored.append(contentsOf: fresh)
        selectedIDs.subtract(ids)
        if let id = activeSelectionID, ids.contains(id) { activeSelectionID = nextSelection }
        if let id = previewItemID, ids.contains(id) { previewItemID = nil }
        if fresh.count == 1 {
            showToast("已忽略 \(fresh[0].name)")
        } else {
            showToast("已忽略 \(fresh.count) 项（本次扫描内生效）")
        }
    }

    /// 忽略「当前筛选 + 搜索」下的全部条目（而不是所有可见条目，避免误伤被筛掉的项）
    func ignoreAll() {
        ignore(filteredItems)
    }

    /// 写入永久忽略规则，并从本轮结果 / 会话忽略里拿掉（重扫时由规则过滤）
    func promoteIgnoredToRules(_ targets: [ResourceItem]) {
        guard !targets.isEmpty else { return }
        let patterns = targets.compactMap { Self.ignorePattern(for: $0) }
        guard !patterns.isEmpty else { return }
        let added = importRules(patterns)
        let ids = Set(targets.map(\.id))
        let nextSelection = nextActiveSelectionID(removing: ids)
        items.removeAll { ids.contains($0.id) }
        sessionIgnored.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        if let id = activeSelectionID, ids.contains(id) { activeSelectionID = nextSelection }
        if let id = previewItemID, ids.contains(id) { previewItemID = nil }
        if added > 0 {
            showToast(added == 1
                ? "已写入永久规则，重扫后不再出现"
                : "已写入 \(added) 条永久规则，重扫后不再出现")
        } else {
            showToast("对应规则已存在，已从本轮结果移除")
        }
    }

    func promoteAllIgnoredToRules() {
        promoteIgnoredToRules(sessionIgnored)
    }

    /// 生成可写入 ignore_rules 的相对路径模式
    static func ignorePattern(for item: ResourceItem) -> String? {
        let path = item.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        if item.directoryPath != nil {
            return path.hasSuffix("/") ? path : path + "/"
        }
        return path
    }

    // MARK: - 删除

    /// 单项直接进废纸篓；多项先弹确认
    func requestDelete(_ targets: [ResourceItem]) {
        let items = targets.filter { !unavailableIDs.contains($0.id) }
        guard !items.isEmpty, !isDeleting else { return }
        if items.count == 1 {
            trash(items)
        } else {
            pendingDeletion = items
            showingDeleteConfirm = true
        }
    }

    func requestDeleteSelected() {
        requestDelete(filteredItems.filter { selectedIDs.contains($0.id) })
    }

    /// 删除「当前筛选 + 搜索」下的全部条目（而不是所有可见条目）
    func requestDeleteAllVisible() {
        requestDelete(filteredItems)
    }

    /// 删除当前筛选结果里的高置信度未引用项
    func requestDeleteConfirmedUnused() {
        requestDelete(filteredItems.filter(\.isConfirmedUnused))
    }

    func confirmPendingDeletion() {
        let items = pendingDeletion
        pendingDeletion = []
        showingDeleteConfirm = false
        trash(items)
    }

    func cancelPendingDeletion() {
        pendingDeletion = []
        showingDeleteConfirm = false
    }

    /// 真实删除：全部经 TrashService 走系统废纸篓（可恢复）；可选同步清理 pbxproj
    func trash(_ targets: [ResourceItem]) {
        guard !targets.isEmpty else { return }
        isDeleting = true
        let shouldCleanPbx = cleanPbxprojOnDelete && !isMockMode
        let xcodeprojURL = project?.xcodeprojURL
        Task { @MainActor in
            let outcome = await TrashService.recycle(targets)
            var pbxCleaned = 0
            var pbxError: String?
            if shouldCleanPbx, let xcodeprojURL, !outcome.trashedIDs.isEmpty {
                let trashedItems = targets.filter { outcome.trashedIDs.contains($0.id) }
                let paths = trashedItems.map { $0.directoryPath ?? $0.absolutePath }
                do {
                    let clean = try PBXProjCleaner.removeReferences(
                        xcodeprojURL: xcodeprojURL,
                        absolutePaths: paths
                    )
                    pbxCleaned = clean.removedObjectCount
                } catch {
                    pbxError = error.localizedDescription
                }
            }
            self.isDeleting = false
            self.applyTrashOutcome(outcome, pbxCleanedObjects: pbxCleaned, pbxError: pbxError)
        }
    }

    private func applyTrashOutcome(
        _ outcome: TrashOutcome,
        pbxCleanedObjects: Int = 0,
        pbxError: String? = nil
    ) {
        let removed = Set(outcome.removedIDs)
        if !removed.isEmpty {
            // 先算邻近焦点，再改 items；否则 filteredItems 已变，只能落到第一条并触发整页滚动
            let nextSelection = nextActiveSelectionID(removing: removed)
            items.removeAll { removed.contains($0.id) }
            sessionIgnored.removeAll { removed.contains($0.id) }
            selectedIDs.subtract(removed)
            if let id = activeSelectionID, removed.contains(id) {
                activeSelectionID = nextSelection
            }
            if let id = previewItemID, removed.contains(id) { previewItemID = nil }
        }
        for failure in outcome.failures {
            unavailableIDs.insert(failure.item.id)
        }

        var message: String
        if outcome.failures.isEmpty {
            guard !removed.isEmpty else { return }
            message = "已移到废纸篓 \(removed.count) 项，可从废纸篓恢复"
        } else if outcome.trashedIDs.isEmpty {
            showToast("删除失败：\(outcome.failures[0].reason)")
            return
        } else {
            message = "已移到废纸篓 \(removed.count) 项，\(outcome.failures.count) 项失败并标记为不可用"
        }
        if pbxCleanedObjects > 0 {
            message += "；已清理 \(pbxCleanedObjects) 处工程引用"
        } else if let pbxError {
            message += "；工程引用未清理（\(pbxError)）"
        }
        showToast(message)
    }

    /// 把删除失败、目标已不存在的条目从列表里移除，避免一直占着「不可用」状态
    func removeUnavailableFromList() {
        let ids = unavailableIDs
        guard !ids.isEmpty else { return }
        let nextSelection = nextActiveSelectionID(removing: ids)
        items.removeAll { ids.contains($0.id) }
        sessionIgnored.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        unavailableIDs = []
        if let id = activeSelectionID, ids.contains(id) {
            activeSelectionID = nextSelection
        }
        showToast("已从列表移除 \(ids.count) 个不可用项")
    }

    /// 导出当前筛选 / 搜索结果，生成带 BOM 的 CSV
    func exportVisibleReport() {
        let targets = filteredItems
        guard !targets.isEmpty else {
            showToast("当前没有可导出的条目")
            return
        }
        do {
            if let url = try ReportExporter.export(items: targets, projectName: projectTitle) {
                showToast("已导出 \(targets.count) 项到 \(url.lastPathComponent)")
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func restoreAllIgnored() {
        sessionIgnored = []
        showToast("已恢复全部忽略项")
    }

    func addUserRule(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !rules.contains(where: { $0.pattern == trimmed }) else {
            showToast("规则已存在：\(trimmed)")
            return
        }
        rules.append(IgnoreRule(pattern: trimmed))
        persistUserRules()
        showToast("已添加规则 \(trimmed)")
    }

    func deleteUserRule(_ id: UUID) {
        rules.removeAll { $0.id == id && !$0.isBuiltIn }
        persistUserRules()
    }

    /// 从 .gitignore 导入规则：去重后合并到用户规则
    @discardableResult
    func importRules(_ patterns: [String]) -> Int {
        var added = 0
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !rules.contains(where: { $0.pattern == trimmed }) else { continue }
            rules.append(IgnoreRule(pattern: trimmed))
            added += 1
        }
        if added > 0 { persistUserRules() }
        return added
    }

    /// 选择 .gitignore 并导入
    func importGitignoreFile() {
        guard let url = ProjectPicker.chooseGitignoreFile() else { return }
        let patterns = IgnoreRulesStore.patterns(inGitignoreAt: url)
        guard !patterns.isEmpty else {
            showToast("「\(url.lastPathComponent)」里没有可用规则")
            return
        }
        let added = importRules(patterns)
        showToast(added > 0
            ? "已从 \(url.lastPathComponent) 导入 \(added) 条规则"
            : "「\(url.lastPathComponent)」的规则都已存在")
    }

    /// 恢复单条会话级忽略
    func restore(_ item: ResourceItem) {
        sessionIgnored.removeAll { $0.id == item.id }
    }
}
