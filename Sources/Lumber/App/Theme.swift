import SwiftUI
import AppKit

// MARK: - 系统推荐配色
//
// 全部改用语义色 / 系统强调色：
// · 背景：windowBackgroundColor（自动跟随明暗模式与壁纸色调）
// · 强调：Color.accentColor（尊重用户在「系统设置 › 外观」里选的强调色）
// · 类型：系统调色板 blue / purple / orange / gray，不再硬编码 RGB

extension Color {
    /// 主内容画布
    static var lumberCanvas: Color { Color(nsColor: .windowBackgroundColor) }
    /// 强调色：跟随系统强调色
    static var lumberAccent: Color { .accentColor }
}

extension ResourceType {
    /// 类型主色（系统调色板）
    var tint: Color {
        switch self {
        case .image: return .blue
        case .color: return .pink
        case .xib: return .purple
        case .code: return .orange
        case .data: return .teal
        case .other: return .gray
        }
    }
}

// MARK: - 液态玻璃面板
//
// 统一封装 glassEffect，保证全 App 玻璃层参数一致：
// · .regular           标准玻璃
// · .interactive()     可交互玻璃（悬停/按压有光影反馈）
// · .tint(Color)       着色玻璃（选中态、强调操作）

struct GlassSurface: ViewModifier {
    var shape: AnyShape
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(effect, in: shape)
    }

    private var effect: Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// 圆角矩形玻璃面板
    func glassPanel(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(
            shape: AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)),
            tint: tint,
            interactive: interactive
        ))
    }

    /// 任意形状玻璃（胶囊、圆形等）
    func glassPanel<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: AnyShape(shape), tint: tint, interactive: interactive))
    }
}

// MARK: - 液态玻璃分隔
//
// 用一条带高光棱线的极细玻璃边替代不透明分割线：
// 上半部一道冷高光 → 中间 .separator 发丝线 → 下方自然投影，形成「玻璃断面」的层次。

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(height: 0.5)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 1)
                    .blendMode(.plusLighter)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 共享 UI 元件
//
// 侧栏按钮、列表行操作、预览窗口浮动操作是同一套视觉语言：
// 26pt 图标热区 + 24pt 悬停圆 + 胶囊实体底板 + 56pt 状态徽章。
// 这里做成唯一实现，避免三处各自漂移。

/// 胶囊内的圆形图标按钮
///
/// 默认就是同一种观感；`deepensOnHover` 描述「图标平时次要、悬停加深为主色」的侧栏行为，
/// 列表 / 预览里的按钮本身已是语义色（如红色删除），不需要这套切换。
struct CircleIconButton: View {
    let symbol: String
    let help: String
    /// 常态图标色
    var tint: Color = .secondary
    /// 悬停时图标是否加深为主色
    var deepensOnHover = false
    /// 悬停圆的填充色（固定色按钮传自身颜色，视觉更统一）
    var hoverTint: Color = Color.lumberAccent
    /// 悬停圆的最大不透明度
    var hoverFillOpacity: CGFloat = 0.28
    var disabled = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(foreground)
                .frame(width: 26, height: 26)
                .background {
                    Circle()
                        .fill(hoverTint.opacity(isHovering && !disabled ? hoverFillOpacity : 0))
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var foreground: Color {
        guard deepensOnHover else { return tint }
        return isHovering ? Color.primary : Color.secondary
    }
}

/// 胶囊实体底板（controlBackgroundColor + 轻投影）
///
/// 列表 cell、导航栏控件板、预览浮动操作都要「非透明底」，否则内容会从控件后面透出来。
struct PillSurface: ViewModifier {
    var horizontal: CGFloat = 2
    var vertical: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            )
    }
}

/// 判定状态徽章（高置信度 / 待确认 / 未加入 target / 不可用）
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color
    var help: String = ""

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        .help(help)
    }
}

extension View {
    func pillSurface(horizontal: CGFloat = 2, vertical: CGFloat = 1) -> some View {
        modifier(PillSurface(horizontal: horizontal, vertical: vertical))
    }
}

// MARK: - Toast

struct ToastView: View {
    var message: String
    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassPanel(in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - 行首缩略图

struct ResourceThumbnail: View {
    let item: ResourceItem
    var size: CGFloat = 46

    @State private var loadedImage: NSImage?

    init(item: ResourceItem, size: CGFloat = 46) {
        self.item = item
        self.size = size
        // 首次出现时同步命中内存缓存：滚动复用 / 来回滚动不会出现「先空后图」的闪跳
        let cached = item.type == .image && !item.absolutePath.isEmpty
            ? ImageStore.shared.cachedThumbnail(for: item)
            : nil
        _loadedImage = State(initialValue: cached)
    }

    /// 真实图片异步加载；mock 条目（无绝对路径）继续用程序生成的渐变图
    private var displayImage: NSImage? {
        loadedImage ?? (item.absolutePath.isEmpty ? MockImages.shared.thumbnail(for: item) : nil)
    }

    var body: some View {
        Group {
            if item.type == .image, let image = displayImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: item.type.symbolName)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(item.type.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // 缩略图底板用纯色 tint：小面积上玻璃几乎看不出差别，却会在滚动时不断重采样
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(item.type.tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .task(id: item.id) {
            guard item.type == .image, !item.absolutePath.isEmpty, loadedImage == nil else { return }
            let image = await ImageStore.shared.thumbnail(for: item)
            // 图片就位时不要带隐式动画，否则会在滚动中闪一下淡入
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) { loadedImage = image }
        }
    }
}
