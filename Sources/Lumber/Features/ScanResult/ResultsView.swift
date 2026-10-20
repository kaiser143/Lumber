import AppKit
import SwiftUI

// MARK: - 结果列表页入口

struct ResultsScreen: View {
    var body: some View {
        ResultsView()
    }
}

// MARK: - 结果列表

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        cardList
            .onKeyPress(.space) { openSelectedPreview(); return .handled }
            .onKeyPress(.return) { openSelectedPreview(); return .handled }
            .onKeyPress(.delete) { model.requestDeleteSelected(); return .handled }
            .onKeyPress(.upArrow) { model.stepSelection(-1); return .handled }
            .onKeyPress(.downArrow) { model.stepSelection(1); return .handled }
            .onKeyPress(.leftArrow) { model.stepSelection(-1); return .handled }
            .onKeyPress(.rightArrow) { model.stepSelection(1); return .handled }
            .alert("移到废纸篓？", isPresented: deleteConfirmationBinding) {
                Button("移到废纸篓", role: .destructive) { model.confirmPendingDeletion() }
                Button("取消", role: .cancel) { model.cancelPendingDeletion() }
            } message: {
                Text("将把 \(model.pendingDeletion.count) 项（共 \(model.pendingDeletionSizeText)）移到废纸篓，之后可从废纸篓恢复。")
            }
    }

    /// 批量删除的二次确认（删除全部 / 删除选中多项）
    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.showingDeleteConfirm },
            set: { newValue in
                if !newValue { model.cancelPendingDeletion() }
            }
        )
    }

    /// 空格/回车：为当前选中项打开独立预览窗口（同一资源重复触发只会聚焦已有窗口）
    private func openSelectedPreview() {
        guard let item = model.selectionForPreview else { return }
        model.select(item)
        openWindow(id: "preview", value: item)
    }

    // MARK: - 卡片列表（无头部，内容区直接铺列表）

    private var cardList: some View {
        ScrollView {
            GlassEffectContainer(spacing: 10) {
                LazyVStack(spacing: 10) {
                    ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ResultCard(item: item, index: index)
                            .id(item.id)
                    }
                    if model.filteredItems.isEmpty {
                        emptyState
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        // 硬边裁切：列表贴到导航栏时不产生模糊透出
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(Color.lumberCanvas)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(model.visibleItems.isEmpty ? "没有发现未引用的资源" : "没有匹配的筛选结果")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 导航栏右侧控件（筛选下拉 + 操作菜单 + 重新扫描）

struct ResultsNavControls: View {
    @Environment(AppModel.self) private var model
    @State private var showIgnoredSheet = false

    var body: some View {
        HStack(spacing: 6) {
            if !model.sessionIgnored.isEmpty { ignoredEntry }
            filterMenu
            actionsMenu
            refreshButton
        }
        // 非透明底：整行放在一块深色板上，避免和卡片区穿帮
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .sheet(isPresented: $showIgnoredSheet) {
            IgnoredItemsSheet()
        }
    }

    // MARK: 筛选下拉

    /// 下拉里每个分组带数量（待确认开关生效后也相应变化，搜索词不影响分组数量）
    private func groupLabel(for type: ResourceType?) -> String {
        if let type {
            return "\(type.rawValue) \(model.scopedTypeCounts[type, default: 0])"
        }
        return "全部 \(model.scopedItems.count)"
    }

    private var filterMenu: some View {
        Menu {
            Picker("筛选", selection: Binding(get: { model.filter }, set: { model.filter = $0 })) {
                Text(groupLabel(for: nil)).tag(Optional<ResourceType>.none)
                ForEach(ResourceType.allCases, id: \.self) { type in
                    Text(groupLabel(for: type)).tag(Optional(type))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Toggle("只看待确认（\(model.needsReviewCount)）", isOn: Binding(
                get: { model.reviewOnly },
                set: { model.reviewOnly = $0 }
            ))
        } label: {
            HStack(spacing: 4) {
                Text(groupLabel(for: model.filter))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .glassPanel(in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("按类型筛选")
    }

    // MARK: 批量操作

    private var actionsMenu: some View {
        Menu {
            Button("全部忽略") { model.ignoreAll() }
                .disabled(model.visibleItems.isEmpty)
            Button("移到废纸篓（选中）") { model.requestDeleteSelected() }
                .disabled(model.selectedIDs.isEmpty || model.isDeleting)
            Button("全部移到废纸篓…") { model.requestDeleteAllVisible() }
                .disabled(model.visibleItems.isEmpty || model.isDeleting)
            if !model.sessionIgnored.isEmpty {
                Divider()
                Button("查看已忽略（\(model.sessionIgnored.count)）…") { showIgnoredSheet = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .glassPanel(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("批量操作")
    }

    // MARK: 已忽略入口

    private var ignoredEntry: some View {
        Button {
            showIgnoredSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9, weight: .semibold))
                Text("已忽略 \(model.sessionIgnored.count)")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .glassPanel(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("查看并恢复本次扫描中忽略的条目")
    }

    // MARK: 重新扫描

    private var refreshButton: some View {
        Button {
            model.rescan()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .glassPanel(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("重新扫描")
    }
}
