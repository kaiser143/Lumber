import SwiftUI

// MARK: - 结果卡片行（对标图1：玻璃卡片 + 缩略图 + 渐变胶囊 + 圆形操作按钮）

struct ResultCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let item: ResourceItem
    let index: Int

    @State private var trashHovered = false

    private var isSelected: Bool { model.selectedIDs.contains(item.id) }
    /// 删除失败 / 目标已被外部移动
    private var isUnavailable: Bool { model.unavailableIDs.contains(item.id) }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailButton
            infoColumn
            Spacer(minLength: 8)
            actionColumn
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .glassPanel(
            cornerRadius: 14,
            tint: isSelected ? Color.lumberAccent.opacity(0.22) : nil,
            interactive: true
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.lumberAccent.opacity(0.85) : Color.white.opacity(0.001),
                    lineWidth: 1.4
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { model.select(item) }
        .onTapGesture(count: 2) { openPreviewWindow() }
        .help(item.note.map { "\(item.relativePath)\n\($0)" } ?? item.relativePath)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    /// 打开独立预览窗口（同一资源重复打开只会聚焦该窗口）
    private func openPreviewWindow() {
        model.select(item)
        openWindow(id: "preview", value: item)
    }

    // MARK: - 缩略图（点击打开预览窗口）

    private var thumbnailButton: some View {
        Button { openPreviewWindow() } label: {
            ResourceThumbnail(item: item, size: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 标题 + 渐变胶囊 + 大小/路径

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                if isUnavailable {
                    unavailableBadge
                } else if item.isConfirmedUnused {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .help("高置信度未引用：工程文本中完全没有出现该名称")
                } else if item.needsReview {
                    reviewBadge
                }
            }
            HStack(spacing: 6) {
                Text(item.sizeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.quaternary)
                Text(item.relativePath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    /// 「待确认」标记：命中了模糊信号（注释、名称片段、仅有 target 引用等）
    private var reviewBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("待确认")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.orange.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5))
        .help(item.note ?? "存在模糊信号，建议人工确认后再删除")
    }

    /// 删除失败 / 目标已不存在
    private var unavailableBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("不可用")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.red.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.red.opacity(0.35), lineWidth: 0.5))
        .help("删除失败或目标已被外部移动，无法再次操作")
    }

    // MARK: - 右侧圆形操作按钮

    private var actionColumn: some View {
        HStack(spacing: 8) {
            GhostCircleButton(symbol: "doc.on.doc", help: "复制文件名") {
                copyFileName()
            }
            GhostCircleButton(symbol: "folder", help: "在 Finder 中显示") {
                revealInFinder()
            }
            trashButton
        }
    }

    /// 复制资源名到系统剪贴板（imageset 已去掉 .imageset 后缀，代码文件为完整文件名）
    private func copyFileName() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.name, forType: .string)
        model.showToast("已复制「\(item.name)」")
    }

    /// 在 Finder 中定位真实文件（imageset 这种聚合条目定位到目录）；mock 条目没有磁盘路径
    private func revealInFinder() {
        guard !item.absolutePath.isEmpty else {
            model.showToast("演示条目没有真实文件路径")
            return
        }
        let target = item.directoryPath ?? item.absolutePath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

    /// 圆形删除按钮：液态玻璃 + 深色，悬停变红；真实移入系统废纸篓
    private var trashButton: some View {
        Button { model.requestDelete([item]) } label: {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .glassPanel(
                    in: Circle(),
                    tint: trashHovered ? Color.red : Color.black.opacity(0.72),
                    interactive: true
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isUnavailable ? "目标已不存在，无法删除" : "移到废纸篓（可从废纸篓恢复）")
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.4 : 1)
        .onHover { trashHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: trashHovered)
    }
}

// MARK: - 圆形玻璃图标按钮（各自独立悬停态，避免一行里多个按钮同时变亮）

private struct GhostCircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .glassPanel(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
