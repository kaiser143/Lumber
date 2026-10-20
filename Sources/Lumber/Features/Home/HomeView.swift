import SwiftUI
import UniformTypeIdentifiers

// MARK: - 空白首页（整块画布即拖放区）
//
// 拖入真实 .xcodeproj / 工程目录即可扫描；
// 非法文件不弹窗，在拖放区显示红色边框 + 文案，几秒后自动恢复。

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(nsImage: MockImages.shared.appEmblem)
                .resizable()
                .aspectRatio(contentMode: .fit)
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
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.5)
                .padding(8)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            // onDrop 必须同步返回，真正的文件读取放到异步任务里
            Task { await model.acceptDrop(providers: providers) }
            return true
        }
        .onTapGesture { model.chooseProject() }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: model.dropError)
    }

    private var borderColor: Color {
        if model.dropError != nil { return .red.opacity(0.75) }
        if hovering { return Color.lumberAccent.opacity(0.55) }
        return .clear
    }
}
