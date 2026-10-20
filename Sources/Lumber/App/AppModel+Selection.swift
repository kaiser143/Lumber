import Foundation

// MARK: - 选中与预览导航
//
// 主窗口负责选中态；预览窗口通过 previewItemID 记录自己当前展示的条目，
// 左右方向键切换时不会回写主窗口的选中项。

extension AppModel {
    func select(_ item: ResourceItem) {
        selectedIDs = [item.id]
    }

    func stepSelection(_ delta: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        let current = list.firstIndex(where: { selectedIDs.contains($0.id) }) ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), list.count - 1)
        selectedIDs = [list[next].id]
    }

    /// 供主窗口回车/空格打开预览窗口时取「要预览的条目」
    var selectionForPreview: ResourceItem? {
        filteredItems.first { selectedIDs.contains($0.id) } ?? filteredItems.first
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
