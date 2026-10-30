import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 结果列表

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    /// 键盘快捷键需要列表先拿到焦点；搜索框提交后会把焦点还给列表
    @FocusState private var listFocused: Bool

    var body: some View {
        cardList
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onAppear { listFocused = true }
            .onChange(of: model.listFocusRequest) { _, _ in listFocused = true }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                Task { await model.acceptDrop(providers: providers) }
                return true
            }
            .onKeyPress(.space) { openSelectedPreview(); return .handled }
            .onKeyPress(.return) { openSelectedPreview(); return .handled }
            .onKeyPress(.delete) { model.requestDeleteSelected(); return .handled }
            .onKeyPress(.upArrow) { model.stepSelection(-1); return .handled }
            .onKeyPress(.downArrow) { model.stepSelection(1); return .handled }
            .onKeyPress(.leftArrow) { model.stepSelection(-1); return .handled }
            .onKeyPress(.rightArrow) { model.stepSelection(1); return .handled }
            .onKeyPress(.escape) {
                guard !model.searchText.isEmpty else { return .ignored }
                model.searchText = ""
                return .handled
            }
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                switch press.characters.lowercased() {
                case "a":
                    model.selectAllFiltered()
                    return .handled
                default:
                    return .ignored
                }
            }
            .alert("移到废纸篓？", isPresented: deleteConfirmationBinding) {
                Button("移到废纸篓", role: .destructive) { model.confirmPendingDeletion() }
                Button("取消", role: .cancel) { model.cancelPendingDeletion() }
            } message: {
                Text(deleteConfirmMessage)
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

    private var deleteConfirmMessage: String {
        var text = "将把 \(model.pendingDeletion.count) 项（共 \(model.pendingDeletionSizeText)）移到废纸篓，之后可从废纸篓恢复。"
        if model.cleanPbxprojOnDelete, !model.isMockMode {
            text += " 同时会清理 project.pbxproj 中的对应引用（先备份为 .lumber-bak）。"
        }
        return text
    }

    /// 空格/回车：为当前选中项打开独立预览窗口（同一资源重复触发只会聚焦已有窗口）
    private func openSelectedPreview() {
        guard let item = model.selectionForPreview else { return }
        model.openPreview(item)
        openWindow(id: "preview")
    }

    // MARK: - 卡片列表（无头部，内容区直接铺列表）

    private var cardList: some View {
        // body 求值时只过滤一次，避免 ForEach / emptyState 各自重算整个列表
        let list = model.filteredItems

        return ScrollViewReader { proxy in
            ScrollView {
                // 不要用 GlassEffectContainer 包住懒加载列表：滚动时行不断创建/销毁，
                // 容器会在每次布局变化时重建整块玻璃合成层，表现为 cell 闪一下。
                LazyVStack(spacing: 10) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        ResultCard(item: item, rowIndex: index)
                            .id(item.id)
                    }
                    if list.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            // 硬边裁切：列表贴到导航栏时不产生模糊透出
            .scrollEdgeEffectStyle(.hard, for: .top)
            // 仅方向键切换时滚动；删除/忽略/点击改选中不要动滚动位置
            .onChange(of: model.selectionScrollRequest) { _, _ in
                guard let id = model.activeSelectionID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .background(Color.lumberCanvas)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.visibleItems.isEmpty ? "sparkles" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(emptyStateText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if model.visibleItems.isEmpty {
                if model.sessionIgnored.isEmpty {
                    Button("打开其他工程…") {
                        model.backToHome()
                        model.chooseProject()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("恢复全部忽略（\(model.sessionIgnored.count)）") {
                        model.restoreAllIgnored()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button("清除筛选与搜索") {
                    model.searchText = ""
                    model.filter = nil
                    model.statusFilter = .all
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyStateText: String {
        if !model.visibleItems.isEmpty { return "没有匹配的筛选结果" }
        if !model.sessionIgnored.isEmpty { return "当前结果已全部忽略" }
        return "没有发现未引用的资源"
    }
}

// MARK: - 导航栏右侧控件（搜索 + 筛选 + 操作菜单 + 重新扫描 + 返回首页）

struct ResultsNavControls: View {
    @Environment(AppModel.self) private var model
    @State private var showIgnoredSheet = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        // 行内控件本身就是玻璃（搜索 / 筛选胶囊 / 三个圆按钮），包一层 GlassEffectContainer
        // 让它们融合成一条连续的液态玻璃栏；底下不再垫实底板——那层板会把每块玻璃
        // 各自的高光和相邻控件切开。导航栏本身有实体背景，这里不存在内容穿透的问题。
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                searchField
                filterMenu
                actionsMenu
                refreshButton
                homeButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .sheet(isPresented: $showIgnoredSheet) {
            IgnoredItemsSheet()
        }
        .onChange(of: model.searchFocusRequest) { _, _ in
            searchFocused = true
        }
    }

    // MARK: 搜索

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("搜索名称 / 路径", text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .frame(width: 104)
            .focused($searchFocused)
            .onSubmit {
                searchFocused = false
                model.requestListFocus()
            }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // 与同行其它控件一致改成玻璃；原来是 5.5% 深色填充 + 白描边，
        // 那套依赖底下的实底板，去掉底板后会贴在背景上看不出边界。
        .glassPanel(in: Capsule())
        .help("搜索资源名或相对路径（⌘F）")
    }

    // MARK: 筛选 + 排序 + 状态筛选

    /// 下拉里每个类型分组带数量（状态筛选生效后也相应变化，搜索词不影响分组数量）
    private func groupLabel(for type: ResourceType?) -> String {
        if let type {
            return "\(type.rawValue) \(model.scopedTypeCounts[type, default: 0])"
        }
        return "全部 \(model.scopedItems.count)"
    }

    private func statusLabel(for filter: StatusFilter) -> String {
        "\(filter.rawValue)（\(model.statusFilterCount(for: filter))）"
    }

    /// 菜单胶囊文案：类型 + 非「全部」时的状态
    private var filterMenuTitle: String {
        let typePart = groupLabel(for: model.filter)
        guard model.statusFilter != .all else { return typePart }
        return "\(typePart) · \(model.statusFilter.rawValue)"
    }

    private var filterMenu: some View {
        Menu {
            Picker("类型", selection: Binding(get: { model.filter }, set: { model.filter = $0 })) {
                Text(groupLabel(for: nil)).tag(Optional<ResourceType>.none)
                ForEach(ResourceType.allCases, id: \.self) { type in
                    Text(groupLabel(for: type)).tag(Optional(type))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Picker("状态", selection: Binding(
                get: { model.statusFilter },
                set: { model.statusFilter = $0 }
            )) {
                ForEach(StatusFilter.allCases) { filter in
                    Text(statusLabel(for: filter)).tag(filter)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Menu("排序：\(model.sortOption.rawValue)") {
                Picker("排序", selection: Binding(
                    get: { model.sortOption },
                    set: { model.sortOption = $0 }
                )) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            HStack(spacing: 4) {
                Text(filterMenuTitle)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // 同一行里的圆形按钮都是 interactive，筛选胶囊同为可点控件也保持一致
            .glassPanel(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("按类型 / 判定状态筛选，或排序")
    }

    // MARK: 批量操作

    private var actionsMenu: some View {
        Menu {
            Button("导出当前结果（\(model.filteredItems.count)）…") { model.exportVisibleReport() }
                .disabled(model.filteredItems.isEmpty)
            if !model.unavailableIDs.isEmpty {
                Button("移除不可用项（\(model.unavailableIDs.count)）") {
                    model.removeUnavailableFromList()
                }
            }

            Divider()

            Button("忽略当前结果（\(model.filteredItems.count)）") {
                model.ignoreAll()
            }
            .disabled(model.filteredItems.isEmpty)
            Button(
                "删除高置信度未引用（\(model.filteredItems.filter(\.isConfirmedUnused).count)）…",
                role: .destructive
            ) {
                model.requestDeleteConfirmedUnused()
            }
            .disabled(model.filteredItems.filter(\.isConfirmedUnused).isEmpty || model.isDeleting)
            Button("删除当前结果（\(model.filteredItems.count)）…", role: .destructive) {
                model.requestDeleteAllVisible()
            }
            .disabled(model.filteredItems.isEmpty || model.isDeleting)

            Divider()

            Button("选择其他工程…") { model.chooseProject() }

            if !model.sessionIgnored.isEmpty {
                Divider()
                Button("查看已忽略（\(model.sessionIgnored.count)）…") { showIgnoredSheet = true }
                Button("已忽略全部升格为永久规则") {
                    model.promoteAllIgnoredToRules()
                }
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
        .help("批量操作 / 导出 / 切换工程")
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

    // MARK: 返回首页

    private var homeButton: some View {
        Button {
            model.backToHome()
        } label: {
            Image(systemName: "house")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .glassPanel(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("返回首页，拖入或选择其他工程")
    }
}
