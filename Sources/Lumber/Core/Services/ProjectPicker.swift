import AppKit
import UniformTypeIdentifiers

// MARK: - 选择工程（点击拖放区）

@MainActor
enum ProjectPicker {
    /// 系统注册的 .xcodeproj 类型（拿不到时为 nil，选择面板退化成「只允许目录」）。
    ///
    /// 不能用 `UTType(filenameExtension:)` 代替：它返回的是 `dyn.*` 动态类型，
    /// 而磁盘上 .xcodeproj 解析出来的是系统注册的 `com.apple.xcode.project`，
    /// 两者不相等 → 面板过滤时会把 .xcodeproj 置灰，怎么点都选不上。
    private static var projectType: UTType? {
        if let type = UTType("com.apple.xcode.project"), !type.isDynamic { return type }
        if let type = UTType(filenameExtension: "xcodeproj"), !type.isDynamic { return type }
        return nil
    }

    static func chooseProject() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 Xcode 工程"
        panel.message = "选择 .xcodeproj 工程，或包含工程的文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        // 包按「文件项」处理：点一下 .xcodeproj 就是选中，不会钻进包里
        panel.treatsFilePackagesAsDirectories = false
        // .xcodeproj 满足 com.apple.xcode.project / public.directory，但**不**满足 public.folder，
        // 所以必须把精确类型一起声明；拿不到精确类型时退化成 .directory（目录类一概可选，文件仍被过滤）
        panel.allowedContentTypes = projectType.map { [$0, .folder] } ?? [.directory]
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 选择 .gitignore 文件用于导入忽略规则
    static func chooseGitignoreFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "导入 .gitignore 规则"
        panel.message = "选择工程里的 .gitignore 文件"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
