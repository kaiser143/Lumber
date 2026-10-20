import Foundation

// MARK: - 列表操作：忽略 / 删除（废纸篓）/ 规则增删

extension AppModel {
    func ignore(_ item: ResourceItem) {
        guard !sessionIgnored.contains(where: { $0.id == item.id }) else { return }
        sessionIgnored.append(item)
        selectedIDs.remove(item.id)
        if previewItemID == item.id { previewItemID = nil }
        showToast("已忽略 \(item.name)")
    }

    func ignoreAll() {
        sessionIgnored.append(contentsOf: visibleItems)
        selectedIDs = []
        previewItemID = nil
        showToast("已忽略全部（本次扫描内生效）")
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

    func requestDeleteAllVisible() {
        requestDelete(visibleItems)
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
            inventory.removeAll { removed.contains($0.id) }
            sessionIgnored.removeAll { removed.contains($0.id) }
            selectedIDs.subtract(removed)
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
