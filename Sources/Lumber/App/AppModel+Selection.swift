import Foundation

// MARK: - 选中与预览导航
//
// 主窗口负责选中态；预览窗口通过 previewItemID 记录自己当前展示的条目，
// 左右方向键切换时不会回写主窗口的选中项。

extension AppModel {
    func select(_ item: ResourceItem) {
        selectedIDs = [item.id]
        activeSelectionID = item.id
    }

    /// 打开（或切换）单例预览窗口的内容
    func openPreview(_ item: ResourceItem) {
        select(item)
        previewItemID = item.id
    }

    /// Command 点击：加入 / 移出多选
    func toggleSelection(_ item: ResourceItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
            if activeSelectionID == item.id {
                activeSelectionID = filteredItems.first { selectedIDs.contains($0.id) }?.id
            }
        } else {
            selectedIDs.insert(item.id)
            activeSelectionID = item.id
        }
    }

    /// Shift 点击：从锚点扩展到目标项
    func extendSelection(to item: ResourceItem) {
        let list = filteredItems
        guard let target = list.firstIndex(where: { $0.id == item.id }) else { return }
        let anchorID = activeSelectionID ?? selectedIDs.first
        let anchor = anchorID.flatMap { id in list.firstIndex(where: { $0.id == id }) } ?? target
        let range = anchor <= target ? anchor...target : target...anchor
        selectedIDs = Set(list[range].map(\.id))
        activeSelectionID = item.id
    }

    func selectAllFiltered() {
        selectedIDs = Set(filteredItems.map(\.id))
        activeSelectionID = filteredItems.first?.id
    }

    func clearSelection() {
        selectedIDs = []
        activeSelectionID = nil
    }

    func stepSelection(_ delta: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        let anchorID = activeSelectionID ?? selectedIDs.first
        let current = anchorID.flatMap { id in list.firstIndex(where: { $0.id == id }) }
            ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), list.count - 1)
        let target = list[next]
        selectedIDs = [target.id]
        activeSelectionID = target.id
        selectionScrollRequest += 1
    }

    /// 在真正移除条目之前调用：焦点落在邻近项（优先下一项），避免跳到列表顶部。
    func nextActiveSelectionID(removing removed: Set<UUID>) -> UUID? {
        let list = filteredItems
        guard let currentID = activeSelectionID, removed.contains(currentID) else {
            return activeSelectionID
        }
        guard let index = list.firstIndex(where: { $0.id == currentID }) else {
            return list.first(where: { !removed.contains($0.id) })?.id
        }
        if let next = list[(index + 1)...].first(where: { !removed.contains($0.id) }) {
            return next.id
        }
        return list[..<index].last(where: { !removed.contains($0.id) })?.id
    }

    /// 供主窗口回车/空格打开预览窗口时取「要预览的条目」
    var selectionForPreview: ResourceItem? {
        if let id = activeSelectionID,
           let item = filteredItems.first(where: { $0.id == id }) {
            return item
        }
        return filteredItems.first { selectedIDs.contains($0.id) } ?? filteredItems.first
    }

    /// 预览窗口内左右方向键切换：只在预览窗口自己的上下文中移动
    func stepPreview(from item: ResourceItem, by delta: Int) -> ResourceItem {
        let list = filteredItems
        guard !list.isEmpty else { return item }
        guard let index = list.firstIndex(where: { $0.id == item.id }) else {
            return list.first ?? item
        }
        let next = min(max(index + delta, 0), list.count - 1)
        previewItemID = list[next].id
        return list[next]
    }

}
