import Foundation

// MARK: - 命令行自检
//
//   swift run Lumber --inspect /path/to/DemoApp.xcodeproj
//
// 不开窗口，直接打印解析摘要与扫描统计，方便核对 pbxproj 解析是否正确。

@MainActor
enum CLIInspect {
    static func run(path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            let xcodeprojURL = try ProjectResolver.resolve(url)
            let info = try ProjectLoader.load(xcodeprojURL: xcodeprojURL)

            print("工程：\(info.name)  (\(info.displayName))")
            print("根目录：\(info.rootDirectory.path)")
            print("targets：\(info.targets.isEmpty ? "（无）" : info.targets.joined(separator: ", "))")
            print("主 storyboard：\(info.mainStoryboardName ?? "（未配置）")")
            print("PBXFileReference：\(info.fileReferenceCount) 个；已解析引用路径：\(info.referencedPaths.count) 个")
            print("加入构建阶段：\(info.builtPaths.count) 个；同步根组：\(info.synchronizedRootPaths.count) 个")
            print("同 workspace 的其它工程：\(info.linkedProjects.isEmpty ? "（无）" : info.linkedProjects.joined(separator: ", "))")
            print("整目录引用：\(info.folderReferencePaths.count) 个")
            for folder in info.folderReferencePaths.prefix(10) {
                print("  · \(folder)")
            }
            print("Assets.xcassets：\(info.assetCatalogs.count) 个")
            for catalog in info.assetCatalogs.prefix(20) {
                print("  · \(catalog.relativePath)  条目 \(catalog.entries.count)（imageset \(catalog.imageSetCount)）")
                for entry in catalog.entries.prefix(5) {
                    print("      - \(entry.name)  [\(entry.kind.rawValue)]  \(entry.fileNames.count) 个文件")
                }
            }

            var outcome = ScanOutcome()
            var finished = false
            let patterns = IgnoreRule.builtIn.map(\.pattern) + IgnoreRulesStore.loadPatterns()
            print("忽略规则：\(patterns.count) 条（含内置 \(IgnoreRule.builtIn.count) 条）")
            Task { @MainActor in
                outcome = await ScanEngine().scan(project: info, rules: IgnoreRuleSet(patterns: patterns), options: ScanOptions()) { _ in }
                finished = true
            }
            while !finished {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }

            print("扫描候选资源：\(outcome.items.count) 项（索引 token \(outcome.tokenCount) 个，耗时 \(String(format: "%.2fs", outcome.seconds))）")
            print("按规则跳过：\(outcome.ignoredCount) 个文件/目录")
            print("高置信度未引用：\(outcome.confirmedCount) 项；待确认：\(outcome.uncertainCount) 项；未加入 target：\(outcome.notInTargetCount) 项")
            for (type, count) in outcome.typeCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                print("  \(type.rawValue)：\(count)")
            }
            for item in outcome.listedItems.prefix(40) {
                let flag = item.needsReview ? "?" : "!"
                print("  \(flag) \(item.type.rawValue)  \(item.relativePath)  \(item.sizeText)  — \(item.note ?? "")")
            }
        } catch {
            // 失败必须给非零退出码，否则 CI / 脚本无法感知解析失败
            print("解析失败：\(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }
}
