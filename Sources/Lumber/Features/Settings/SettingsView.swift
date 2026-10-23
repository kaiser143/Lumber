import AppKit
import SwiftUI

// MARK: - 设置页
//
// 扫描选项与「删除时清理 pbxproj」会持久化；忽略规则仍单独落盘。

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("设置")
                    .font(.system(size: 17, weight: .bold))

                settingsCard {
                    Toggle("扫描时把代码文件列为候选（.swift / .m / .h）", isOn: Binding(
                        get: { model.includeCodeFiles },
                        set: { model.includeCodeFiles = $0 }
                    ))
                    Text("关闭后代码文件不再出现在结果里，但它们仍参与引用匹配，不影响图片/XIB 的判定。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Text("扫描目录深度")
                            .font(.system(size: 12))
                        Spacer()
                        Stepper(value: Binding(
                            get: { model.scanDepth },
                            set: { model.scanDepth = $0 }
                        ), in: 4...64) {
                            Text("\(model.scanDepth) 层")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    Divider()
                    Toggle("删除时同步清理 project.pbxproj 引用", isOn: Binding(
                        get: { model.cleanPbxprojOnDelete },
                        set: { model.cleanPbxprojOnDelete = $0 }
                    ))
                    Text("移到废纸篓后，去掉工程里对应的 PBXFileReference / PBXBuildFile，避免 Xcode 里出现红字孤儿引用。写回前会备份为 project.pbxproj.lumber-bak。Assets 内的 imageset 通常无独立引用，会自动跳过。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsCard {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("忽略规则文件")
                                .font(.system(size: 12))
                            Text(IgnoreRulesStore.displayPath)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("在 Finder 中显示") {
                            try? FileManager.default.createDirectory(
                                at: IgnoreRulesStore.directoryURL,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(IgnoreRulesStore.directoryURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("扫描选项会记住；忽略规则单独持久化。所有删除都走系统废纸篓，可从废纸篓恢复。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }
}
