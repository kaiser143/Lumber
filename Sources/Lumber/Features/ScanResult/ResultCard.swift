import SwiftUI

// MARK: - 结果卡片行（缩略图 + 信息 + 胶囊操作按钮）
//
// 列表 cell 不用 glassEffect：液态玻璃自带自适应阴影，LazyVStack 回收时会在
// 快速滚动中闪动；改用静态填充，观感接近且滚动稳定。

struct ResultCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let item: ResourceItem
    /// 用于斑马条纹（偶行浅底 / 奇行更浅灰）
    let rowIndex: Int

    @State private var isHovering = false

    private var isSelected: Bool { model.selectedIDs.contains(item.id) }
    /// 删除失败 / 目标已被外部移动
    private var isUnavailable: Bool { model.unavailableIDs.contains(item.id) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailButton
            infoColumn
            Spacer(minLength: 8)
            actionPill
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(cardFill, in: cardShape)
        .overlay(selectBorder)
        .contentShape(cardShape)
        .onTapGesture { handleTap() }
        .onTapGesture(count: 2) { openPreviewWindow() }
        .contextMenu { cellContextMenu }
        .onHover { isHovering = $0 }
        .help(item.note.map { "\(item.relativePath)\n\($0)" } ?? item.relativePath)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// 对标图1：斑马底 → 悬停冷灰 → 选中强调色。无玻璃、无投影。
    private var cardFill: Color {
        if isSelected {
            return Color.lumberAccent.opacity(0.28)
        }
        if isHovering {
            // 图1 标号1：悬停冷调浅灰
            return Color.primary.opacity(0.09)
        }
        // 斑马：偶行与列表背景一致（透明露出 lumberCanvas），奇行浅灰
        return rowIndex.isMultiple(of: 2)
            ? .clear
            : Color.primary.opacity(0.055)
    }

    /// 右键：忽略 / 移到废纸篓。若点在已多选的行上，对整组选中生效。
    @ViewBuilder
    private var cellContextMenu: some View {
        let targets = contextMenuTargets
        let labelSuffix = targets.count > 1 ? "（\(targets.count)）" : ""

        Button("忽略\(labelSuffix)") {
            model.ignore(targets)
        }
        Button("忽略并写入永久规则\(labelSuffix)") {
            model.promoteIgnoredToRules(targets)
        }
        Button("移到废纸篓\(labelSuffix)", role: .destructive) {
            model.requestDelete(targets)
        }
        .disabled(targets.allSatisfy { model.unavailableIDs.contains($0.id) } || model.isDeleting)
    }

    /// 右键目标：点在已选中的多选行上 → 全部选中项；否则 → 当前行
    private var contextMenuTargets: [ResourceItem] {
        if isSelected, model.selectedIDs.count > 1 {
            return model.filteredItems.filter { model.selectedIDs.contains($0.id) }
        }
        return [item]
    }

    /// 纯点击单选；⌘ 点击多选；Shift 点击区间选择
    private func handleTap() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            model.toggleSelection(item)
        } else if modifiers.contains(.shift) {
            model.extendSelection(to: item)
        } else {
            model.select(item)
        }
        // 点击行后把键盘焦点交还列表，方向键 / 空格 / Delete 才能继续工作
        model.requestListFocus()
    }

    /// 打开独立预览窗口（同一资源重复打开只会聚焦该窗口）
    private func openPreviewWindow() {
        model.openPreview(item)
        openWindow(id: "preview")
    }

    @ViewBuilder
    private var selectBorder: some View {
        // 悬停只铺底、不加描边（与图1一致）；选中才描强调色边
        if isSelected {
            cardShape
                .strokeBorder(Color.lumberAccent.opacity(0.9), lineWidth: 1.5)
        }
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
                } else if item.notInTarget {
                    notInTargetBadge
                } else if item.needsReview {
                    reviewBadge
                } else if item.isConfirmedUnused {
                    confirmedBadge
                }
                // 悬停时出现在状态徽章右侧
                if isHovering {
                    copyNameButton
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
            // 判定原因常驻：不用悬停 tooltip 才能看到「为什么出现在这里」
            if let reason = item.judgmentReasonText {
                Text(reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(judgmentReasonColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var judgmentReasonColor: Color {
        if item.notInTarget { return .blue.opacity(0.85) }
        if item.needsReview { return .orange.opacity(0.9) }
        return Color.secondary
    }

    /// 文件名旁的复制按钮（仅行悬停时出现）
    private var copyNameButton: some View {
        Button {
            copyFileName()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("复制文件名")
        .accessibilityLabel("复制文件名")
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }

    /// 「高置信度」：工程里完全找不到引用，可优先清理
    private var confirmedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("高置信度")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.green.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5))
        .help(item.note ?? "工程文本与构建阶段中均未找到引用")
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

    /// 工程里有、但没有加入 target 构建阶段：不会进包，通常是漏配
    private var notInTargetBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "target")
                .font(.system(size: 10, weight: .semibold))
            Text("未加入 target")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.blue.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.blue.opacity(0.35), lineWidth: 0.5))
        .help(item.note ?? "在工程导航器中，但没有加入任何 target 构建阶段")
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

    // MARK: - 右侧胶囊操作按钮（对标图1）

    /// 浅粉底胶囊 + 轻投影，内含「在 Finder 中显示」与「移到废纸篓」
    private var actionPill: some View {
        HStack(spacing: 2) {
            PillIconButton(
                symbol: "folder",
                tint: Color.primary.opacity(0.72),
                help: "在 Finder 中显示"
            ) {
                revealInFinder()
            }
            PillIconButton(
                symbol: "trash",
                tint: .red,
                help: isUnavailable ? "目标已不存在，无法删除" : "移到废纸篓（可从废纸篓恢复）",
                disabled: isUnavailable
            ) {
                model.requestDelete([item])
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        // 与导航栏控件板一致：controlBackgroundColor + 同款投影
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
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
}

// MARK: - 胶囊内图标按钮（图1：线框图标 + 小号粉色悬停圆）

private struct PillIconButton: View {
    let symbol: String
    let tint: Color
    let help: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background {
                    // 悬停高亮小圆（与外包胶囊无关）
                    Circle()
                        .fill(Color.lumberAccent.opacity(isHovering ? 0.28 : 0))
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
    }
}
