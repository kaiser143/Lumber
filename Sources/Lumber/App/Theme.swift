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
        case .xib: return .purple
        case .code: return .orange
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

// MARK: - 顶部三段式小标题（对标「默认 → Q3 · 均衡」）

struct TopHint: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .glassPanel(in: Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
            .padding(.bottom, 6)
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
        .glassPanel(
            cornerRadius: 9,
            tint: item.type.tint.opacity(0.12)
        )
        .task(id: item.id) {
            guard item.type == .image, !item.absolutePath.isEmpty else { return }
            loadedImage = await ImageStore.shared.thumbnail(for: item)
        }
    }
}

// MARK: - 系统色系渐变胶囊（对标图1的压缩率标签）

struct GradientBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            )
            .shadow(color: Color.accentColor.opacity(0.28), radius: 4, y: 1)
    }
}
