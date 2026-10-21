import SwiftUI
import AppKit

/// 应用图标入口：优先渲染 `Resources/LumberIcon.svg`（即 Option O 设计），
/// 让首页、关于页、运行时 Dock 图标与 .app 包图标保持同一套视觉。
/// 资源不可用时退回手绘版本，避免界面出现空图标。
struct LumberIcon: View {
    var body: some View {
        Group {
            if let image = LumberIconAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                FallbackLumberIcon()
            }
        }
        .frame(width: 256, height: 256)
        .accessibilityHidden(true)
    }
}

/// 图标资源定位：先看 .app 包内资源，再按源码/工作目录回溯，兼容 `swift run` 与打包后的 bundle。
private enum LumberIconAsset {
    static let image: NSImage? = locate().flatMap { NSImage(contentsOf: $0) }

    private static func locate() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("LumberIcon.svg"))
            candidates.append(resources.appendingPathComponent("LumberIcon.icns"))
        }

        // 开发态：从本文件位置回溯到工程根目录
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // …/Sources/Lumber/App
            .deletingLastPathComponent()   // …/Sources/Lumber
            .deletingLastPathComponent()   // …/Sources
            .deletingLastPathComponent()   // 工程根目录
        candidates.append(sourceRoot.appendingPathComponent("Resources/LumberIcon.svg"))

        let workingRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        candidates.append(workingRoot.appendingPathComponent("Resources/LumberIcon.svg"))

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

/// 手绘兜底图标（旧设计），仅在图标资源缺失时出现。
struct FallbackLumberIcon: View {
    private let gold = Color(red: 0.96, green: 0.83, blue: 0.24)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 43, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.47, green: 0.48, blue: 0.47), Color(red: 0.10, green: 0.11, blue: 0.11)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.39, green: 0.41, blue: 0.40), Color(red: 0.12, green: 0.14, blue: 0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(6)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .frame(width: 104, height: 3)
                        .offset(y: 13)
                }
                .frame(width: 172, height: 190)
                .shadow(color: .black.opacity(0.28), radius: 12, y: 9)

            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(Color(red: 0.76, green: 0.78, blue: 0.71).opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 8]))
                .frame(width: 91, height: 67)
                .rotationEffect(.degrees(5))
                .offset(y: -47)

            ZStack {
                Circle().fill(Color(red: 0.15, green: 0.16, blue: 0.15)).frame(width: 38, height: 38)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.86, green: 0.88, blue: 0.83), Color(red: 0.34, green: 0.36, blue: 0.34)], center: .init(x: 0.35, y: 0.25), startRadius: 1, endRadius: 20))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                Circle().fill(Color(red: 0.31, green: 0.33, blue: 0.32)).frame(width: 16, height: 16)
                Ellipse().fill(.white.opacity(0.55)).frame(width: 8, height: 5).offset(x: -5, y: -7)
            }
            .offset(y: -63)

            ForEach(Array([CGPoint(x: 50, y: -77), CGPoint(x: 33, y: -63), CGPoint(x: -33, y: -64), CGPoint(x: -46, y: -75)].enumerated()), id: \.offset) { _, point in
                Circle().fill(gold).frame(width: point.x == 50 ? 7 : 5, height: point.x == 50 ? 7 : 5).offset(x: point.x, y: point.y)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.08, blue: 0.08))
                    .frame(width: 112, height: 58)
                    .offset(y: 5)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white, Color(red: 0.73, green: 0.76, blue: 0.76)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 116, height: 66)
                    .overlay {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(red: 0.15, green: 0.22, blue: 0.42))
                                .frame(width: 92, height: 37)
                                .overlay(alignment: .top) {
                                    UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9)
                                        .fill(LinearGradient(colors: [Color(red: 0.76, green: 0.85, blue: 1), Color(red: 0.30, green: 0.43, blue: 0.72)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 86, height: 26)
                                        .overlay(alignment: .topLeading) {
                                            Path { path in
                                                path.move(to: CGPoint(x: 4, y: 16))
                                                path.addLine(to: CGPoint(x: 18, y: 6))
                                                path.addLine(to: CGPoint(x: 31, y: 14))
                                            }
                                            .stroke(gold, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                                            .frame(width: 36, height: 24)
                                        }
                                }
                            Capsule().fill(.white.opacity(0.65)).frame(width: 86, height: 2).padding(.bottom, 5)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.75), lineWidth: 1.5))
            }
            .offset(y: 50)
        }
        .frame(width: 256, height: 256)
    }
}
