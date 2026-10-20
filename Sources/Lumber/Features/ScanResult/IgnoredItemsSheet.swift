import SwiftUI

// MARK: - 「已忽略」清单
//
// 会话级忽略只在本次扫描内生效（不持久化），这里可以逐条或一次性恢复。

struct IgnoredItemsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            footer
        }
        .padding(18)
        .frame(width: 540, height: 400)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("本次扫描已忽略（\(model.sessionIgnored.count)）")
                    .font(.system(size: 14, weight: .bold))
                Text("忽略只在本次扫描内生效，不写入规则文件；重新扫描后这些条目会重新出现。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("全部恢复") { model.restoreAllIgnored() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.sessionIgnored.isEmpty)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.sessionIgnored.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("暂无忽略项")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.sessionIgnored) { item in
                        row(for: item)
                    }
                }
            }
        }
    }

    private func row(for item: ResourceItem) -> some View {
        HStack(spacing: 8) {
            ResourceThumbnail(item: item, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(item.sizeText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("恢复") { model.restore(item) }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.lumberCanvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Text("想永久排除？到「忽略规则」里添加通配规则。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

