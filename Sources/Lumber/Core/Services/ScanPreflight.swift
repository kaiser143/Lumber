import Foundation

// MARK: - 扫描前预统计
//
// 只为两件事走一遍目录：算出文件总数（进度用）和找出子工程根目录。
// 子工程（内含其它 .xcodeproj 的目录）整体跳过，避免把依赖库/示例工程源码当成冗余。

struct Preflight: Sendable {
    var totalFiles = 0
    var subprojectRoots: Set<String> = []
}

extension ScanEngine {
    /// 命中忽略规则的文件/目录不计入总数，保证进度条分母与实际扫描量一致
    func preflight(root: URL, rules: IgnoreRuleSet) -> Preflight {
        var result = Preflight()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        let rootPath = root.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let relativePath = Self.relativePath(of: url, in: root)

            guard isDirectory else {
                if !rules.isIgnored(relativePath: relativePath, isDirectory: false) {
                    result.totalFiles += 1
                }
                continue
            }

            let name = url.lastPathComponent
            if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
                let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
                if parentPath != rootPath { result.subprojectRoots.insert(parentPath) }
                enumerator.skipDescendants()
                continue
            }
            if Self.shouldSkip(directoryNamed: name)
                || rules.isIgnored(relativePath: relativePath, isDirectory: true) {
                enumerator.skipDescendants()
                continue
            }
            // Assets.xcassets 及其条目目录由扫描阶段整体聚合，内部文件不计入进度分母
            let ext = url.pathExtension.lowercased()
            if ext == "xcassets" || Self.assetDirectoryExtensions.contains(ext) {
                enumerator.skipDescendants()
            }
        }
        return result
    }
}
