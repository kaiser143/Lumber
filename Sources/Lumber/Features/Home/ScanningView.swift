import SwiftUI

// MARK: - 扫描中状态页
//
// 展示当前阶段、当前路径、已扫描文件数，以及按类型统计的已发现冗余数。

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                header
                ProgressView(value: model.progress.fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.regular)
                phaseLine
                pathLine
                counters
                typeChips
            }
            .padding(20)
            .frame(maxWidth: 560)
            .glassPanel(cornerRadius: 20)

            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 30)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.projectName.isEmpty ? "正在扫描" : model.projectTitle)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(Int(model.progress.fraction * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var phaseLine: some View {
        Text(model.progress.phaseDisplayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var pathLine: some View {
        Text(model.progress.currentPath.isEmpty ? "准备中…" : model.progress.currentPath)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    // MARK: - 计数

    private var counters: some View {
        HStack(spacing: 16) {
            stat(label: "已扫描", value: scannedText)
            stat(label: "发现", value: "\(model.progress.foundCount)")
            if model.progress.uncertainCount > 0 {
                stat(label: "待确认", value: "\(model.progress.uncertainCount)")
            }
            if model.progress.ignoredCount > 0 {
                stat(label: "按规则跳过", value: "\(model.progress.ignoredCount)")
            }
            Spacer()
            Button("取消") { model.cancelScan() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var scannedText: String {
        let total = model.progress.totalCount
        return total > 0 ? "\(model.progress.scannedCount)/\(total)" : "\(model.progress.scannedCount)"
    }

    /// 各类型发现数（评估阶段显示候选数，判定阶段显示已确认的冗余数）
    private var typeChips: some View {
        HStack(spacing: 8) {
            ForEach(ResourceType.allCases, id: \.self) { type in
                typeChip(type, count: model.progress.typeCounts[type] ?? 0)
            }
        }
    }

    private func typeChip(_ type: ResourceType, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: type.symbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(type.tint)
            Text(type.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .glassPanel(in: Capsule())
        .opacity(count == 0 ? 0.45 : 1)
    }

    private func stat(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }
}
