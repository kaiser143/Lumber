import SwiftUI

// MARK: - 单例预览窗口
//
// `Window`（而不是按 value 创建的 WindowGroup）保证同一时间只有一个预览窗口。
// 切换资源时只更新 AppModel.previewItemID，窗口内容随之替换。

struct PreviewWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let item = currentItem {
                PreviewView(item: item)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("没有可预览的资源")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.lumberCanvas)
            }
        }
    }

    private var currentItem: ResourceItem? {
        guard let id = model.previewItemID else { return nil }
        return model.items.first { $0.id == id }
    }
}

// MARK: - 预览窗口内容（对齐参考图1：无标题栏、图片尽量铺满、四边等距、圆角）

struct PreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// 顶部留白：比左右底更大，让右上角浮动按钮在顶部条带里上下居中
    private static let topInset: CGFloat = 40
    /// 左 / 右 / 底边距
    private static let sideInset: CGFloat = 10
    /// 顶部文件名需要让开窗口红黄绿按钮
    private static let titleLeading: CGFloat = 78
    /// 图片圆角
    private static let imageCorner: CGFloat = 12
    /// 窗口最大尺寸占屏幕可视区的比例
    ///
    /// 预览属于「看内容」的窗口，按 HIG 的可用性要求不能顶满屏幕：
    /// 四周各留 5%，既保证内容够大，又能看到桌面、方便拖动窗口和察觉背后的其它窗口。
    /// 屏幕可视区（visibleFrame）本身已扣除菜单栏与 Dock。
    private static let maxScreenFraction: CGFloat = 0.9
    /// 窗口最小尺寸，与 LumberApp 里预览窗口的 frame 下限保持一致
    private static let minWindowSize = NSSize(width: 300, height: 260)

    @State private var currentItem: ResourceItem
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var rotation: Double = 0
    @State private var hostWindow: NSWindow?
    /// 预览窗口的本地键盘事件监视器（空格 / Esc / 左右方向键）
    @State private var keyMonitor: Any?
    /// 真实图片（预览大图），mock 条目为 nil
    @State private var loadedImage: NSImage?
    /// 真实文本内容（代码 / XIB / Storyboard），mock 条目为 nil
    @State private var loadedText: String?
    /// 窗口当前请求展示的条目（由 PreviewWindow 传入；切换资源时更新，但不重建整个视图）
    private let incomingItem: ResourceItem

    init(item: ResourceItem) {
        incomingItem = item
        _currentItem = State(initialValue: item)
    }

    var body: some View {
        // 隐藏标题栏后系统会在顶部留出 titlebar 高度的安全区（实测 32pt）。
        // 按「窗口真实高度」布局再整体上移，图片就能贴到窗口顶边、四边等距。
        GeometryReader { geo in
            let reserve = geo.safeAreaInsets.top
            content
                .frame(width: geo.size.width, height: geo.size.height + reserve)
                .background(Color.lumberCanvas)
                .offset(y: -reserve)
        }
        .background(PreviewWindowAccessor { window in
            hostWindow = window
            applyWindowLimits(window)
            fitWindowToImage(window)
            installKeyMonitor(for: window)
        })
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            // 换到更小的屏幕时，上限和当前尺寸都要重新收一遍
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            applyWindowLimits(window)
            fitWindowToImage(window)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // 关闭后重新打开同一个 Window 场景时，确保键盘监视器仍然在位
            guard let window = note.object as? NSWindow else { return }
            if hostWindow == nil { hostWindow = window }
            guard window === hostWindow else { return }
            installKeyMonitor(for: window)
        }
        .navigationTitle(currentItem.name)
        .task(id: currentItem.id) { await loadFileContent() }
        .onChange(of: incomingItem.id) { _, _ in
            guard currentItem.id != incomingItem.id else { return }
            currentItem = incomingItem
            resetTransform()
        }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.space) { dismiss(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onExitCommand { dismiss() }
    }

    /// 从磁盘读取当前条目的真实内容（图片解码 / 文本读取），读完再按图片比例校正窗口尺寸
    private func loadFileContent() async {
        loadedImage = nil
        loadedText = nil
        guard !currentItem.absolutePath.isEmpty else { return }

        switch currentItem.type {
        case .image:
            loadedImage = await ImageStore.shared.preview(for: currentItem)
        case .code, .xib:
            let path = currentItem.absolutePath
            loadedText = await Task.detached(priority: .userInitiated) {
                TextFileLoader.read(at: path)
            }.value
        case .color, .data, .other:
            break
        }
        if let hostWindow { fitWindowToImage(hostWindow) }
    }

    /// 条目已在主窗口被忽略/删除时，窗口降级为占位
    private var isStale: Bool {
        !model.items.contains { $0.id == currentItem.id }
    }

    private func step(_ delta: Int) {
        guard !isStale else { return }
        currentItem = model.stepPreview(from: currentItem, by: delta)
        resetTransform()
        if let hostWindow { fitWindowToImage(hostWindow) }
    }

    // MARK: - 键盘事件
    //
    // 预览窗口里图片不可聚焦、代码预览是可选中的 ScrollView，
    // SwiftUI 的 onKeyPress 依赖焦点，实际经常收不到空格 / Esc。
    // 这里在窗口级别装本地监视器：只拦截本窗口、无 Command 修饰的按键。

    private func installKeyMonitor(for window: NSWindow) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window,
                  !event.modifierFlags.contains(.command) else { return event }
            switch event.keyCode {
            case 49: // 空格
                dismiss()
                return nil
            case 53: // Esc
                dismiss()
                return nil
            case 123: // ←
                step(-1)
                return nil
            case 124: // →
                step(1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    /// 预览窗口的最大尺寸：不超过屏幕可视区的 90%，同时兜住拖拽放大与跨屏切换
    private func applyWindowLimits(_ window: NSWindow) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let limits = NSSize(
            width: max(Self.minWindowSize.width, (visible.width * Self.maxScreenFraction).rounded(.down)),
            height: max(Self.minWindowSize.height, (visible.height * Self.maxScreenFraction).rounded(.down))
        )
        window.minSize = Self.minWindowSize
        window.maxSize = limits

        // 已经超出上限（上一次在大屏幕上打开过）就地收回，保持顶边不动
        let frame = window.frame
        guard frame.width > limits.width || frame.height > limits.height else { return }
        var resized = frame
        resized.size.width = min(frame.width, limits.width)
        resized.size.height = min(frame.height, limits.height)
        resized.origin.y = frame.maxY - resized.height
        window.setFrame(resized, display: true)
    }

    /// 按图片实际比例调整窗口尺寸：图片区域 = 窗口内容区 - 边距（左右 10 / 上 40 / 下 10）
    ///
    /// 注意隐藏标题栏后标题栏仍然占窗口高度（约 32pt），内容区从它下面开始。
    /// 适配时必须把这块高度加回去，否则图片区域会比预期矮一截，图片只能被裁。
    private func fitWindowToImage(_ window: NSWindow) {
        guard let image = previewImage else { return }
        let iw = image.size.width, ih = image.size.height
        guard iw > 1, ih > 1 else { return }

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let horizontalInset = Self.sideInset * 2
        let verticalInset = Self.topInset + Self.sideInset
        let titlebarHeight = max(window.frame.height - window.contentLayoutRect.height, 0)

        // 不超过屏幕可视区的上限，也不超过图片原始像素（避免把小图放大糊掉）
        let scale = min(
            (visible.width * Self.maxScreenFraction - horizontalInset) / iw,
            (visible.height * Self.maxScreenFraction - verticalInset - titlebarHeight) / ih,
            1
        )

        let targetW = max(iw * scale + horizontalInset, 280)
        let targetH = max(ih * scale + verticalInset, 220) + titlebarHeight

        var frame = window.frame
        let topY = frame.maxY
        frame.size = NSSize(width: targetW, height: targetH)
        frame.origin.y = topY - targetH
        window.setFrame(frame, display: true)
    }

    private func resetTransform() {
        zoom = 1
        baseZoom = 1
        rotation = 0
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.2), 4)
        baseZoom = zoom
    }

    // MARK: - 右上角浮动操作（标题栏隐藏后，忽略/删除浮在图片上）

    private var windowActions: some View {
        HStack(spacing: 6) {
            FloatingCircleButton(icon: "eye.slash", help: "忽略此资源", disabled: isStale) {
                model.ignore(currentItem)
                dismiss()
            }
            FloatingCircleButton(icon: "trash", help: "移到废纸篓（可从废纸篓恢复）", isDestructive: true, disabled: isStale) {
                model.requestDelete([currentItem])
                dismiss()
            }
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if isStale {
            staleState
        } else {
            switch currentItem.type {
            case .image: imageArea
            case .code, .xib: codeArea
            case .color, .data, .other: infoArea
            }
        }
    }

    private var previewImage: NSImage? {
        if let loadedImage { return loadedImage }
        // 演示条目没有真实路径，回落到内置渐变示例图
        return currentItem.absolutePath.isEmpty ? MockImages.shared.preview(for: currentItem) : nil
    }

    // MARK: 图片：铺满 + 圆角 + 左下角尺寸/大小 + 底部中央缩放条

    private var imageArea: some View {
        GeometryReader { geo in
            let w = max(geo.size.width - Self.sideInset * 2, 40)
            let h = max(geo.size.height - Self.topInset - Self.sideInset, 40)
            Group {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        // 保持图片宽高比：完整显示，不把上下/左右裁掉
                        .aspectRatio(contentMode: .fit)
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: Self.imageCorner, style: .continuous))
                        .scaleEffect(zoom)
                        .rotationEffect(.degrees(rotation))
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = min(max(baseZoom * value, 0.2), 4)
                                }
                                .onEnded { _ in baseZoom = zoom }
                        )
                } else {
                    RoundedRectangle(cornerRadius: Self.imageCorner, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: w, height: h)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: Self.topInset + h / 2)
        }
        // 放大后溢出的部分裁在窗口内，避免图片爬到窗口圆角之外
        .clipped()
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottomLeading) { sizeCard }
        .overlay(alignment: .bottom) { zoomBar }
    }

    /// 顶部条：左侧文件名（让开红黄绿），右侧浮动按钮，两者同高垂直居中
    private var topBar: some View {
        HStack(spacing: 10) {
            Text(currentItem.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            windowActions
        }
        .frame(height: 24)
        .padding(.leading, Self.titleLeading)
        .padding(.trailing, Self.sideInset)
        // 24pt 高的条带 + 8pt 上边距 → 中心落在 y=20，即 topInset(40) 的一半
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 左下角：尺寸 + 文件大小（对齐参考图左下角卡片）
    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let size = previewImage?.size {
                Text("\(Int(size.width))px × \(Int(size.height))px")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(currentItem.sizeText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if currentItem.needsReview, let note = currentItem.note {
                Text("待确认 · \(note)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 12)
        .padding(.leading, Self.sideInset)
        .padding(.bottom, Self.sideInset)
    }

    /// 底部中央：缩放与旋转
    private var zoomBar: some View {
        HStack(spacing: 12) {
            Button { setZoom(zoom - 0.1) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("缩小")

            Button { setZoom(1) } label: {
                Text(String(format: "%.1fx", zoom))
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 32)
            }
            .buttonStyle(.plain)
            .help("恢复 100%")

            Button { setZoom(zoom + 0.1) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("放大")

            Divider().frame(height: 13)

            Button { rotation += 90 } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.plain)
            .help("旋转 90°")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .glassPanel(in: Capsule(), interactive: true)
        .padding(.bottom, Self.sideInset)
    }

    // MARK: 代码 / XIB

    private var codeArea: some View {
        ScrollView {
            Text(codeText)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassPanel(cornerRadius: 16)
                .padding(Self.sideInset)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// 真实文件内容优先；mock 条目回落到示例文本
    private var codeText: String {
        if let loadedText { return loadedText }
        return currentItem.type == .code ? MockData.sampleSwiftCode : MockData.sampleXibXML
    }

    // MARK: 其他类型：属性卡片

    private var infoArea: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                infoRow("文件名", currentItem.name)
                GlassDivider()
                infoRow("相对路径", currentItem.relativePath)
                if !currentItem.absolutePath.isEmpty {
                    GlassDivider()
                    infoRow("绝对路径", currentItem.absolutePath)
                }
                GlassDivider()
                infoRow("大小", currentItem.sizeText)
                GlassDivider()
                infoRow("类型", currentItem.type.rawValue)
                if let note = currentItem.note {
                    GlassDivider()
                    infoRow("判定", note)
                }
                if let modified = modificationText {
                    GlassDivider()
                    infoRow("修改时间", modified)
                }
            }
            .padding(16)
            .glassPanel(cornerRadius: 16)
        }
        .padding(Self.sideInset)
        .padding(.top, Self.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var modificationText: String? {
        guard !currentItem.absolutePath.isEmpty,
              let date = TextFileLoader.modificationDate(at: currentItem.absolutePath) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var staleState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("该资源已被删除或忽略")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("按 Esc 或点窗口左上角红点关闭")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 预览窗顶部浮动圆钮（悬停高亮）

private struct FloatingCircleButton: View {
    let icon: String
    let help: String
    var isDestructive: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    private var hoverTint: Color {
        isDestructive ? Color.red.opacity(0.18) : Color.primary.opacity(0.12)
    }

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(width: 24, height: 24)
                .glassPanel(in: Circle(), interactive: true)
                .overlay {
                    Circle().fill(isHovering && !disabled ? hoverTint : Color.clear)
                }
                .overlay {
                    Circle().strokeBorder(
                        Color.primary.opacity(isHovering && !disabled ? 0.20 : 0),
                        lineWidth: 0.5
                    )
                }
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(disabled ? 0.32 : (isHovering ? 1 : 0.85)))
                }
                .scaleEffect(isHovering && !disabled ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
        .disabled(disabled)
    }
}

// MARK: - 取到承载预览内容的 NSWindow（用于按图片比例自适应窗口尺寸）

private struct PreviewWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
