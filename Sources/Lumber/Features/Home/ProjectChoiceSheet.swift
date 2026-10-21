import SwiftUI

// MARK: - 多工程选择
//
// 拖入包含多个 .xcodeproj 的目录、或 .xcworkspace 时，先让用户明确选择要扫描的工程。

struct ProjectChoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("发现多个工程")
                    .font(.system(size: 17, weight: .bold))
                Text("请选择要扫描的 .xcodeproj。依赖工程（Pods / Carthage）已自动排除。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.pendingProjects, id: \.self) { url in
                        projectRow(url)
                    }
                }
            }
            .frame(maxHeight: 320)

            HStack {
                Spacer()
                Button("取消") {
                    model.cancelProjectChoice()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 300)
        .background(Color.lumberCanvas)
    }

    private func projectRow(_ url: URL) -> some View {
        Button {
            model.choosePendingProject(url)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lumberAccent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
