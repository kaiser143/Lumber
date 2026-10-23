import AppKit
import SwiftUI

// MARK: - 版本信息

/// 裸二进制（`swift run`）没有 .app bundle，Info.plist 可能为空，
/// 这里兜底成 Resources/Info.plist 里的同一套版本号。
enum LumberInfo {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildVersion: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// 「1.0」或「1.0 (1)」
    static var versionText: String {
        guard let buildVersion else { return marketingVersion }
        return "\(marketingVersion) (\(buildVersion))"
    }

    static var systemText: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    static var copyText: String {
        "Lumber \(versionText) · \(systemText)"
    }
}

// MARK: - 关于页

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heroCard
                rulesCard
                footer
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 图标 + 名称 + 简介

    private var heroCard: some View {
        VStack(spacing: 10) {
            LumberIcon()
                .scaleEffect(84 / 256)
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)

            Text("Lumber")
                .font(.system(size: 22, weight: .bold))

            HStack(spacing: 8) {
                Text("版本 \(LumberInfo.versionText)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.lumberCanvas.opacity(0.6),
                        in: Capsule()
                    )

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(LumberInfo.copyText, forType: .string)
                    model.showToast("已复制版本信息")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("复制版本信息")
            }

            Text("Xcode 工程冗余资源清理工具")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("扫描工程里没有被引用的图片、XIB / Storyboard 与代码文件，预览确认后移入废纸篓（可恢复）。解析与判定全部在本机完成，不上传代码。删除时可选同步清理 project.pbxproj 引用（写回前备份为 .lumber-bak），默认在设置中开启。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .glassPanel(cornerRadius: 18)
    }

    // MARK: - 忽略规则文件位置

    private var rulesCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("判定采用静态文本匹配，运行时拼接的资源名只能归为「待确认」或漏报；详细限制见 README。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Copyright © 2026 Lumber · 仓库暂未附带开源许可证。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }
}
