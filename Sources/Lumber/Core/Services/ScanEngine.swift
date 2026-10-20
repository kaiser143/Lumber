import Foundation

// MARK: - 扫描进度快照（跨线程传递，不可变）

struct ScanUpdate: Sendable {
    var fraction: Double = 0
    var phaseText: String = ""
    var currentPath: String = ""
    var scannedCount: Int = 0
    var totalCount: Int = 0
    /// 已发现的候选资源数
    var foundCount: Int = 0
    var uncertainCount: Int = 0
    /// 命中忽略规则而跳过的文件/目录数
    var ignoredCount: Int = 0
    var typeCounts: [ResourceType: Int] = [:]
}

// MARK: - 扫描选项（设置页可调，仅本次运行有效）

struct ScanOptions: Sendable {
    /// 是否把代码文件列为清理候选（引用索引始终包含代码文本）
    var includeCodeFiles = true
    /// 最大扫描深度，超过则不再下探
    var maxDepth = 24
}

// MARK: - 扫描结果

struct ScanOutcome: Sendable {
    /// 全部候选资源（含被引用项，unreferenced = false）
    var items: [ResourceItem] = []
    var scannedFiles: Int = 0
    var typeCounts: [ResourceType: Int] = [:]
    var uncertainCount: Int = 0
    var ignoredCount: Int = 0
    var tokenCount: Int = 0
    var seconds: Double = 0

    var listedItems: [ResourceItem] { items.filter(\.unreferenced) }
    var confirmedCount: Int { items.filter(\.isConfirmedUnused).count }
}

// MARK: - 扫描引擎
//
// 两阶段流水线：
// 1. 单次目录遍历：收集候选资源 + 同时把文本文件喂进引用索引（注释单独进 loose 索引）
// 2. 判定：把候选逐条交给 ReferenceJudge，得出 已引用 / 待确认 / 高置信度未引用
//
// 全程在 actor 内、off-main 执行；进度按 80ms 节流回主线程。

actor ScanEngine {
    fileprivate static let textExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "metal", "intentdefinition",
        "xib", "storyboard", "plist", "strings", "stringsdict",
        "json", "js", "ts", "tsx", "jsx", "html", "htm", "css", "md",
    ]

    /// 这些资源集合不参与清理（AppIcon / 颜色 / 符号等由构建设置引用）
    fileprivate static let ignoredAssetKinds: Set<String> = [
        "colorset", "dataset", "appiconset", "symbolset", "launchimage",
        "imagestack", "spriteatlas", "brandassets", "solidimagestack",
    ]

    static let maxIndexedBytes = 1_500_000
    fileprivate static let progressInterval: TimeInterval = 0.08

    func scan(
        project: ProjectInfo,
        rules: IgnoreRuleSet,
        options: ScanOptions,
        onUpdate: @escaping @MainActor @Sendable (ScanUpdate) -> Void
    ) async -> ScanOutcome {
        let started = Date()
        let root = project.rootDirectory

        await onUpdate(ScanUpdate(fraction: 0.02, phaseText: "统计工程文件数量"))

        let preflight = preflight(root: root, rules: rules)
        let totalFiles = preflight.totalFiles
        if Task.isCancelled { return ScanOutcome() }

        var builder = ReferenceIndexBuilder()
        var candidates: [ScanCandidate] = []
        var scanned = 0
        var ignoredCount = 0
        var lastEmit = Date.distantPast
        var typeCounts: [ResourceType: Int] = [:]

        func emit(_ path: String) async {
            let now = Date()
            guard now.timeIntervalSince(lastEmit) > Self.progressInterval else { return }
            lastEmit = now
            let fraction = totalFiles > 0
                ? 0.05 + 0.70 * Double(scanned) / Double(totalFiles)
                : 0.35
            await onUpdate(ScanUpdate(
                fraction: fraction,
                phaseText: "遍历工程目录并建立引用索引",
                currentPath: path,
                scannedCount: scanned,
                totalCount: totalFiles,
                foundCount: candidates.count,
                ignoredCount: ignoredCount,
                typeCounts: typeCounts
            ))
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return ScanOutcome() }
                let values = try? url.resourceValues(forKeys: keys)
                let relativePath = Self.relativePath(of: url, in: root)

                if values?.isDirectory == true {
                    let ext = url.pathExtension.lowercased()
                    if Self.depth(of: relativePath) >= options.maxDepth {
                        // 超过设置的最大深度：整棵子树不再下探
                        enumerator.skipDescendants()
                    } else if Self.shouldSkip(directoryNamed: url.lastPathComponent)
                        || preflight.subprojectRoots.contains(url.standardizedFileURL.path) {
                        enumerator.skipDescendants()
                    } else if rules.isIgnored(relativePath: relativePath, isDirectory: true) {
                        enumerator.skipDescendants()
                        ignoredCount += 1
                    } else if ext == "imageset" {
                        enumerator.skipDescendants()
                        if let candidate = Self.makeImageSetCandidate(at: url, root: root) {
                            candidates.append(candidate)
                            typeCounts[.image, default: 0] += 1
                        }
                    } else if Self.ignoredAssetKinds.contains(ext) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if rules.isIgnored(relativePath: relativePath, isDirectory: false) {
                    ignoredCount += 1
                    continue
                }
                if Self.depth(of: relativePath) > options.maxDepth { continue }

                scanned += 1
                let absolutePath = url.standardizedFileURL.path
                let isInAssetCatalog = absolutePath.contains(".xcassets/")
                let ext = url.pathExtension.lowercased()

                if !isInAssetCatalog, Self.textExtensions.contains(ext) {
                    let text = Self.readText(at: url)
                    if let candidate = Self.textCandidate(
                        for: url, root: root, size: values?.fileSize ?? 0, text: text
                    ), options.includeCodeFiles || candidate.type != .code {
                        candidates.append(candidate)
                        typeCounts[candidate.type, default: 0] += 1
                    }
                    if let text {
                        builder.addText(text)
                    }
                }

                await emit(absolutePath)
            }
        }

        if Task.isCancelled { return ScanOutcome() }
        let index = builder.build()
        return await judge(
            project: project, candidates: candidates, index: index,
            scanned: scanned, totalFiles: totalFiles, ignoredCount: ignoredCount,
            started: started, onUpdate: onUpdate
        )
    }

    // MARK: - 判定与汇总

    private func judge(
        project: ProjectInfo,
        candidates: [ScanCandidate],
        index: ReferenceIndex,
        scanned: Int,
        totalFiles: Int,
        ignoredCount: Int,
        started: Date,
        onUpdate: @escaping @MainActor @Sendable (ScanUpdate) -> Void
    ) async -> ScanOutcome {
        await onUpdate(ScanUpdate(
            fraction: 0.78,
            phaseText: "判定冗余（共 \(candidates.count) 个候选资源）",
            scannedCount: scanned,
            totalCount: totalFiles,
            ignoredCount: ignoredCount
        ))

        let judge = ReferenceJudge(project: project, index: index)
        var items: [ResourceItem] = []
        items.reserveCapacity(candidates.count)
        var uncertainCount = 0
        var listedCount = 0
        var listedTypeCounts: [ResourceType: Int] = [:]

        for (offset, candidate) in candidates.enumerated() {
            if Task.isCancelled { return ScanOutcome() }
            let item = Self.makeItem(from: candidate, verdict: judge.verdict(for: candidate))
            if item.unreferenced {
                listedCount += 1
                listedTypeCounts[item.type, default: 0] += 1
                if item.needsReview { uncertainCount += 1 }
            }
            items.append(item)

            if offset % 100 == 0 {
                await onUpdate(ScanUpdate(
                    fraction: 0.78 + 0.2 * Double(offset) / Double(max(candidates.count, 1)),
                    phaseText: "判定冗余",
                    currentPath: candidate.relativePath,
                    scannedCount: scanned,
                    totalCount: totalFiles,
                    foundCount: listedCount,
                    uncertainCount: uncertainCount,
                    ignoredCount: ignoredCount,
                    typeCounts: listedTypeCounts
                ))
            }
        }

        items.sort { lhs, rhs in
            if lhs.unreferenced != rhs.unreferenced { return lhs.unreferenced }
            if lhs.isConfirmedUnused != rhs.isConfirmedUnused { return lhs.isConfirmedUnused }
            if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes > rhs.sizeBytes }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        await onUpdate(ScanUpdate(
            fraction: 1,
            phaseText: "汇总结果",
            scannedCount: scanned,
            totalCount: totalFiles,
            foundCount: listedCount,
            uncertainCount: uncertainCount,
            ignoredCount: ignoredCount,
            typeCounts: listedTypeCounts
        ))

        return ScanOutcome(
            items: items,
            scannedFiles: scanned,
            typeCounts: listedTypeCounts,
            uncertainCount: uncertainCount,
            ignoredCount: ignoredCount,
            tokenCount: index.tokenCount,
            seconds: Date().timeIntervalSince(started)
        )
    }
}

// MARK: - 目录过滤

extension ScanEngine {
    /// 这些目录/包不参与扫描：子工程、预编译框架、已打包产物
    private static let skippedBundleSuffixes = [
        ".xcodeproj", ".xcworkspace", ".xcframework", ".framework",
        ".bundle", ".app", ".appex", ".xctest", ".docc", ".playground",
    ]

    static func shouldSkip(directoryNamed name: String) -> Bool {
        if skippedBundleSuffixes.contains(where: { name.hasSuffix($0) }) { return true }
        if ProjectLoader.skippedDirectories.contains(name) { return true }
        return name == ".git"
    }

    static func relativePath(of url: URL, in root: URL) -> String {
        ProjectLoader.relativePath(url, in: root)
    }

    /// 相对路径的层级数（用于最大扫描深度限制）
    static func depth(of relativePath: String) -> Int {
        relativePath.split(separator: "/").count
    }
}

