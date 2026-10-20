import SwiftUI

@main
struct LumberApp: App {
    @State private var model = AppModel()

    init() {
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
        // 隐藏标题栏：让侧边栏材质向上延伸，红黄绿按钮浮在侧栏之上（对标图1/图2）
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开工程…") { model.chooseProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("重新扫描") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.project == nil && !model.isMockMode)
            }
        }

        // 预览：独立窗口（同一资源重复打开只会聚焦，不新建）
        WindowGroup("预览", id: "preview", for: ResourceItem.self) { $item in
            if let item {
                PreviewView(item: item)
                    .environment(model)
                    .frame(minWidth: 300, minHeight: 260)
            }
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)
        // 预览窗口隐藏标题栏：图片铺满，红黄绿浮在图片之上（对齐参考图1）
        .windowStyle(.hiddenTitleBar)
    }
}
