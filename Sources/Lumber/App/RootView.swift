import SwiftUI

// MARK: - App 外壳：窄边栏 + 主区域 + Toast

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // 侧边栏全高延伸到窗口顶部；标题文字放在导航栏（内容区顶部固定条带）
        NavigationSplitView(columnVisibility: .constant(.all), preferredCompactColumn: .constant(.detail)) {
            SidebarView()
                // 固定宽度 86pt，不允许用户拖动调整（min/ideal/max 相等即锁定）
                .navigationSplitViewColumnWidth(82)
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
        // 隐藏窗口工具栏底色，让侧栏材质真正透到窗口顶部
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // 窗口标题跟随当前工程（隐藏标题栏后仍用于窗口菜单 / Mission Control）
        .background(WindowTitleAccessor(title: model.windowTitle))
        // --demo=preview：启动即弹出预览窗口，便于验收
        .task {
            if model.previewItemID != nil {
                openWindow(id: "preview")
            }
        }
    }
}

// MARK: - 窄图标边栏（对标图1/图2左侧：浅灰统一、无强选中底色）

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            SidebarButton(
                icon: "tray.and.arrow.down",
                tip: model.page == .scan && model.phase == .results ? "扫描 · 返回首页" : "扫描",
                isActive: model.page == .scan
            ) {
                // 已经在结果页时，再点「扫描」表示开始一个新工程；从规则/设置页返回则保留结果。
                if model.page == .scan, model.phase == .results {
                    model.backToHome()
                } else {
                    model.page = .scan
                }
            }
            SidebarButton(icon: "eye.slash", tip: "忽略规则", isActive: model.page == .rules) {
                model.page = .rules
            }
            Spacer()
            SidebarButton(icon: "info.circle", tip: "关于", isActive: model.page == .about) {
                model.page = .about
            }
            SidebarButton(icon: "slider.horizontal.3", tip: "设置", isActive: model.page == .settings) {
                model.page = .settings
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 44)
        .padding(.bottom, 12)
        .ignoresSafeArea(edges: .top)
    }
}

/// 侧边栏图标按钮：浅灰统一，仅在悬停/选中时叠一层极淡圆底
struct SidebarButton: View {
    let icon: String
    let tip: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hovering || isActive ? Color.primary.opacity(0.09) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tip)
    }
}

// MARK: - 主区域：导航栏 + 页面路由 + Toast

struct DetailView: View {
    @Environment(AppModel.self) private var model

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
        .background(Color.lumberCanvas)
        .overlay(alignment: .bottom) {
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
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: Self.navBarHeight, alignment: .top)
        // 导航栏必须是实体底：列表滚动时内容不能从标题 / 控件后面透出来
        .background(Color.lumberCanvas)
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
