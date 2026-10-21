import Foundation

// MARK: - 列表操作：忽略 / 删除（废纸篓）/ 规则增删

extension AppModel {
    func ignore(_ item: ResourceItem) {
        guard !sessionIgnored.contains(where: { $0.id == item.id }) else { return }
        sessionIgnored.append(item)
        selectedIDs.remove(item.id)
        if activeSelectionID == item.id { activeSelectionID = filteredItems.first?.id }
        if previewItemID == item.id { previewItemID = nil }
        showToast("已忽略 \(item.name)")
    }

    /// 忽略「当前筛选 + 搜索」下的全部条目（而不是所有可见条目，避免误伤被筛掉的项）
    func ignoreAll() {
        let targets = filteredItems
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        sessionIgnored.append(contentsOf: targets)
        selectedIDs.subtract(ids)
        activeSelectionID = nil
        previewItemID = nil
        showToast("已忽略当前筛选下的 \(targets.count) 项（本次扫描内生效）")
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

    /// 真实删除：全部经 TrashService 走系统废纸篓（可恢复）
    func trash(_ targets: [ResourceItem]) {
        guard !targets.isEmpty else { return }
        isDeleting = true
        Task { @MainActor in
            let outcome = await TrashService.recycle(targets)
            self.isDeleting = false
            self.applyTrashOutcome(outcome)
        }
    }

    private func applyTrashOutcome(_ outcome: TrashOutcome) {
        let removed = Set(outcome.removedIDs)
        if !removed.isEmpty {
            items.removeAll { removed.contains($0.id) }
            sessionIgnored.removeAll { removed.contains($0.id) }
            selectedIDs.subtract(removed)
            if let id = activeSelectionID, removed.contains(id) {
                activeSelectionID = filteredItems.first?.id
            }
            if let id = previewItemID, removed.contains(id) { previewItemID = nil }
        }
        for failure in outcome.failures {
            unavailableIDs.insert(failure.item.id)
        }

        if outcome.failures.isEmpty {
            guard !removed.isEmpty else { return }
            showToast("已移到废纸篓 \(removed.count) 项，可从废纸篓恢复")
        } else if outcome.trashedIDs.isEmpty {
            showToast("删除失败：\(outcome.failures[0].reason)")
        } else {
            showToast("已移到废纸篓 \(removed.count) 项，\(outcome.failures.count) 项失败并标记为不可用")
        }
    }

    /// 把删除失败、目标已不存在的条目从列表里移除，避免一直占着「不可用」状态
    func removeUnavailableFromList() {
        let ids = unavailableIDs
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        sessionIgnored.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        unavailableIDs = []
        if let id = activeSelectionID, ids.contains(id) {
            activeSelectionID = filteredItems.first?.id
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
