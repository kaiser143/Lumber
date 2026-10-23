import SwiftUI

// MARK: - App 外壳：左侧菜单 + 主区域 + Toast

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    /// 侧边菜单是否展开（可用菜单右上角按钮切换，也可 ⌃⌘S / 「显示 > 隐藏菜单」）
    @AppStorage("lumber.sidebarVisible") private var isSidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(isVisible: $isSidebarVisible)
                    .frame(width: SidebarMetrics.width)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            DetailView(isSidebarVisible: $isSidebarVisible)
        }
        // 整个外壳延伸到窗口顶部：红黄绿浮在菜单与内容之上
        .ignoresSafeArea(edges: .top)
        .background(Color.lumberCanvas)
        // 窗口标题跟随当前工程（隐藏标题栏后仍用于窗口菜单 / Mission Control）
        .background(WindowTitleAccessor(title: model.windowTitle))
        // hiddenTitleBar 默认红黄绿偏上；下移使其垂直中心与侧栏「收起」按钮对齐
        .background(TrafficLightsOffset(y: SidebarMetrics.trafficLightsOffsetY))
        // --demo=preview：启动即弹出预览窗口，便于验收
        .task {
            if model.previewItemID != nil {
                openWindow(id: "preview")
            }
        }
    }
}

// MARK: - 侧边菜单尺寸

enum SidebarMetrics {
    /// 菜单列总宽
    static let width: CGFloat = 190
    /// 与红黄绿同高、容纳「收起菜单」按钮的行高
    static let titleRowHeight: CGFloat = 52
    /// 红黄绿相对系统默认下移量（对齐 titleRow 内 28pt 按钮的垂直中心）
    static let trafficLightsOffsetY: CGFloat = 6
    /// 菜单项行高（参考图 1）
    static let itemHeight: CGFloat = 36
    /// 菜单项圆角
    static let itemCornerRadius: CGFloat = 8
    /// 菜单列左右内边距
    static let horizontalInset: CGFloat = 8
}

// MARK: - 侧边菜单（对标图 1 左侧：文字 + 图标、选中蓝色圆角块）

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 2) {
            titleRow

            SidebarItem(
                icon: "tray.and.arrow.down",
                title: "扫描",
                isActive: model.page == .scan
            ) {
                // 已经在结果页时，再点「扫描」表示开始一个新工程；从规则/设置页返回则保留结果。
                if model.page == .scan, model.phase == .results {
                    model.backToHome()
                } else {
                    model.page = .scan
                }
            }
            SidebarItem(
                icon: "eye.slash",
                title: "忽略规则",
                isActive: model.page == .rules
            ) {
                model.page = .rules
            }

            Spacer(minLength: 0)

            SidebarItem(
                icon: "slider.horizontal.3",
                title: "偏好设置",
                isActive: model.page == .settings
            ) {
                model.page = .settings
            }
            SidebarItem(
                icon: "info.circle",
                title: "关于",
                isActive: model.page == .about
            ) {
                model.page = .about
            }
        }
        .padding(.horizontal, SidebarMetrics.horizontalInset)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - 顶部行：菜单右上角的收起按钮

    private var titleRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SidebarToggleButton(icon: "sidebar.left", tip: "隐藏菜单") {
                withAnimation(.easeInOut(duration: 0.22)) { isVisible = false }
            }
            .offset(y: -4)
        }
        .padding(.trailing, 8)
        // 在标题行内垂直居中，再上移 4pt 与红黄绿对齐
        .frame(height: SidebarMetrics.titleRowHeight)
    }

    // MARK: - 外观

    private var sidebarBackground: some View {
        Color.primary.opacity(0.035)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.45))
                    .frame(width: 0.5)
            }
    }
}

// MARK: - 菜单显隐按钮（与 cell / 预览操作同款胶囊底）

struct SidebarToggleButton: View {
    let icon: String
    let tip: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 26, height: 26)
                .background {
                    Circle()
                        .fill(Color.lumberAccent.opacity(hovering ? 0.28 : 0))
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(tip)
    }
}

// MARK: - 菜单项（高度 36、圆角 8，选中为强调色实底）

private struct SidebarItem: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 17, height: 17)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.82))
            .padding(.horizontal, 10)
            .frame(height: SidebarMetrics.itemHeight)
            .background(
                RoundedRectangle(cornerRadius: SidebarMetrics.itemCornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.itemCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .help(title)
    }

    private var fillColor: Color {
        if isActive { return Color.lumberAccent }
        if hovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}

// MARK: - 主区域：导航栏 + 页面路由 + Toast

struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var isSidebarVisible: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch model.page {
                case .scan:
                    switch model.phase {
                    case .idle: HomeView()
                    case .scanning: ScanningView()
                    case .results: ResultsScreen()
                    }
                case .rules: IgnoreRulesView()
                case .settings: SettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Self.navBarHeight)

            navBar
        }
        .ignoresSafeArea(edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lumberCanvas)        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                // 首页自己会在拖放区显示红框提示；其它页面（结果页拖入、扫描中）用底部胶囊提示
                if let error = model.dropError, !(model.page == .scan && model.phase == .idle) {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.red.opacity(0.35), lineWidth: 0.5))
                        .transition(.opacity)
                }
                if let toast = model.toast {
                    ToastView(message: toast)
                }
            }
            .padding(.bottom, 18)
        }
        .animation(.easeOut(duration: 0.2), value: model.toast == nil)
        .animation(.easeOut(duration: 0.2), value: model.dropError)
        .sheet(isPresented: Binding(
            get: { model.showingProjectChoice },
            set: { if !$0 { model.cancelProjectChoice() } }
        )) {
            ProjectChoiceSheet()
        }
    }

    /// 与窗口红黄绿同高的导航栏高度
    private static let navBarHeight: CGFloat = 52

    // MARK: - 导航栏（标题居中 + 结果页右侧控件）

    private var navBar: some View {
        Group {
            if model.page == .scan, model.phase == .results {
                HStack(spacing: 10) {
                    expandButton
                    Text(model.topHintText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    ResultsNavControls()
                }
            } else {
                ZStack {
                    Text(model.topHintText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                    HStack(spacing: 0) {
                        expandButton
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        // 与侧栏 titleRow、红黄绿同一垂直中心
        .frame(maxWidth: .infinity, maxHeight: Self.navBarHeight)
        // 导航栏必须是实体底：列表滚动时内容不能从标题 / 控件后面透出来
        .background(Color.lumberCanvas)
    }

    /// 菜单隐藏后，在内容区左上角提供重新展开的入口（避开红黄绿）
    @ViewBuilder
    private var expandButton: some View {
        if !isSidebarVisible {
            SidebarToggleButton(icon: "sidebar.left", tip: "显示菜单") {
                withAnimation(.easeInOut(duration: 0.22)) { isSidebarVisible = true }
            }
            .offset(y: -4)
            .padding(.leading, 62)
            .transition(.opacity)
        }
    }
}

// MARK: - 窗口标题跟随工程
//
// 窗口用了 .hiddenTitleBar，标题文字不会显示，但仍是窗口菜单 / Mission Control 里的标识。

private struct WindowTitleAccessor: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { view.window?.title = title }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async { nsView.window?.title = title }
    }
}

// MARK: - 红黄绿垂直偏移
//
// AppKit 坐标原点在左下：增大 y 会把按钮往窗口顶部推；要「往下挪」就减小 y。
// 系统在 resize / 样式变化时可能把按钮复位，所以挂在 layout 回调里反复对齐。

private struct TrafficLightsOffset: NSViewRepresentable {
    /// 相对系统默认位置下移的点数
    var y: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(y: y) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.y = y
        context.coordinator.apply(to: nsView.window)
    }

    final class Coordinator {
        var y: CGFloat
        /// 系统默认 y（AppKit 坐标）；目标位置始终是 `base - y`
        private var baseYs: [ObjectIdentifier: CGFloat] = [:]
        /// 上一次成功写进按钮的偏移，用来在改 `y` 时还原 base
        private var appliedY: CGFloat = 0
        private var observations: [NSObjectProtocol] = []

        init(y: CGFloat) { self.y = y }

        deinit {
            for token in observations {
                NotificationCenter.default.removeObserver(token)
            }
        }

        func attach(to view: NSView) {
            let center = NotificationCenter.default
            let apply: (Notification) -> Void = { [weak self, weak view] note in
                guard let self, let view, let window = view.window else { return }
                if let noted = note.object as? NSWindow, noted !== window { return }
                self.apply(to: window)
            }
            observations = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main, using: apply),
                center.addObserver(forName: NSWindow.didResizeNotification, object: nil, queue: .main, using: apply),
            ]
            DispatchQueue.main.async { [weak self, weak view] in
                self?.apply(to: view?.window)
            }
        }

        func apply(to window: NSWindow?) {
            guard let window else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for type in types {
                guard let button = window.standardWindowButton(type) else { continue }
                let id = ObjectIdentifier(button)
                let currentY = button.frame.origin.y
                let baseY: CGFloat
                if let known = baseYs[id] {
                    if abs(currentY - (known - appliedY)) < 0.5 {
                        // 仍是我们上次写的位置
                        baseY = known
                    } else if abs(currentY - known) < 0.5 {
                        // 系统已复位到默认
                        baseY = known
                    } else {
                        // 默认布局变了（例如全屏进出），重记基准
                        baseY = currentY
                        baseYs[id] = currentY
                    }
                } else {
                    baseY = currentY
                    baseYs[id] = currentY
                }
                let targetY = baseY - y
                if abs(currentY - targetY) > 0.5 {
                    button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
                }
            }
            appliedY = y
        }
    }
}
