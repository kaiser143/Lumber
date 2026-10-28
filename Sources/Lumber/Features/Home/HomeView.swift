import SwiftUI
import UniformTypeIdentifiers

// MARK: - 空白首页（整块画布即拖放区）
//
// 拖入真实 .xcodeproj / 工程目录即可扫描；
// 非法文件不弹窗，在拖放区显示红色边框 + 文案，几秒后自动恢复。
// 下方展示最近打开的工程，避免反复拖放。

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    /// 鼠标是否停在点击热区内（悬停反馈 + 手型光标）
    @State private var pointing = false

    var body: some View {
        VStack(spacing: 0) {
            dropZone
            if !model.recentProjects.isEmpty {
                recentSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Spacer()

            // 只有图标 + 文案这一小块响应点击（参考图 1 的红框），整块画布仍可拖入
            clickTarget

            if let error = model.dropError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .transition(.opacity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.5)
                .padding(8)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            Task { await model.acceptDrop(providers: providers) }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: model.dropError)
    }

    /// 点击热区：图标、标题与格式说明，外扩一圈留白但不超过图标宽度太多
    private var clickTarget: some View {
        VStack(spacing: 10) {
            LumberIcon()
                .scaleEffect(92 / 256)
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                .scaleEffect(hovering ? 1.04 : 1)

            Text("鼠标拖入文件或文件夹")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 8)

            Text("XCODEPROJ · XCASSETS · PNG · JPEG · XIB · STORYBOARD · SWIFT")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { model.chooseProject() }
        .onHover { inside in
            pointing = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近工程")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清除") { model.clearRecentProjects() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            ForEach(model.recentProjects.prefix(5)) { recent in
                Button {
                    model.openRecentProject(recent)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.lumberAccent)
                            .frame(width: 22, height: 22)
                            .background(Color.lumberAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(recent.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(((recent.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("从列表移除") { model.removeRecentProject(recent) }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var borderColor: Color {
        if model.dropError != nil { return .red.opacity(0.75) }
        if hovering { return Color.lumberAccent.opacity(0.55) }
        return .clear
    }
}
