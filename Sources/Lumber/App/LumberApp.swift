import SwiftUI
import AppKit

/// 以裸二进制运行时（`swift run` 或在 Xcode 里直接 Run SwiftPM target），进程没有 .app bundle，
/// LaunchServices 会把它登记成 BackgroundOnly，窗口既不显示也不置前。
/// 这里显式提升为常规前台应用，让窗口能正常出现并进 Dock。
final class LumberAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct LumberApp: App {
    @NSApplicationDelegateAdaptor(LumberAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage("lumber.sidebarVisible") private var isSidebarVisible = true

    init() {
        let renderer = ImageRenderer(content: LumberIcon())
        renderer.scale = 2
        NSApplication.shared.applicationIconImage = renderer.nsImage
        // 命令行自检：--inspect <工程路径> 打印解析摘要后直接退出
        if let index = CommandLine.arguments.firstIndex(of: "--inspect"),
           index + 1 < CommandLine.arguments.count {
            CLIInspect.run(path: CommandLine.arguments[index + 1])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 620, minHeight: 460)
        }
        .defaultSize(width: 900, height: 540)
        // 隐藏标题栏：让侧边栏材质向上延伸，红黄绿按钮浮在侧栏之上（对标图1/图2）
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开工程…") { model.chooseProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .sidebar) {
                Button(isSidebarVisible ? "隐藏菜单" : "显示菜单") {
                    isSidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于 Lumber") { model.page = .about }
            }
            CommandGroup(after: .newItem) {
                Button("重新扫描") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.project == nil && !model.isMockMode)
                Button("导出当前结果…") { model.exportVisibleReport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.phase != .results)
                Button("搜索…") { model.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(model.phase != .results)
                Divider()
                Button("返回首页") { model.backToHome() }
                    .disabled(model.phase == .idle && model.page == .scan)
            }
        }

        // 预览：单例窗口。切换资源只替换窗口内容，不会同时出现多个预览窗口。
        Window("预览", id: "preview") {
            PreviewWindow()
                .environment(model)
                .frame(minWidth: 300, minHeight: 260)
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)
        // 预览窗口隐藏标题栏：图片铺满，红黄绿浮在图片之上（对齐参考图1）
        .windowStyle(.hiddenTitleBar)
    }
}
