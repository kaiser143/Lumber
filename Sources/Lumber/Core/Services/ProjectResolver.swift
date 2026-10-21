import Foundation

// MARK: - 拖放目标校验
//
// 把用户拖入 / 选择的东西规整成可解析的 .xcodeproj 目录：
// · .xcodeproj（目录）           → 直接通过
// · .xcworkspace（目录）         → 解析 contents.xcworkspacedata，过滤 Pods 等依赖工程
// · 普通目录                     → 在其中查找 .xcodeproj / .xcworkspace
// · 其它文件                     → 抛错，由界面在拖放区提示
//
// 一个目录里有多个工程时返回全部候选，由界面弹出选择面板，而不是悄悄取字母序第一个。

enum ProjectResolver {
    /// 目录递归查找的最大层数，避免在大仓库里全盘遍历
    private static let maxSearchDepth = 4

    /// 兼容旧调用：返回第一个工程
    static func resolve(_ url: URL) throws -> URL {
        let candidates = try resolveCandidates(url)
        guard let first = candidates.first else {
            throw ProjectDropError.emptyDirectory(url.lastPathComponent)
        }
        return first
    }

    /// 返回所有可扫描的 .xcodeproj（已过滤依赖工程，保持稳定顺序）
    static func resolveCandidates(_ url: URL) throws -> [URL] {
        let candidate = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
        guard exists else {
            throw ProjectDropError.missingProject(candidate.lastPathComponent)
        }

        if candidate.pathExtension == "xcodeproj" {
            guard isDirectory.boolValue else {
                throw ProjectDropError.unsupportedType(candidate.lastPathComponent)
            }
            guard FileManager.default.isReadableFile(atPath: candidate.path) else {
                throw ProjectDropError.noReadPermission(candidate.lastPathComponent)
            }
            return [candidate]
        }

        guard isDirectory.boolValue else {
            throw ProjectDropError.unsupportedType(candidate.lastPathComponent)
        }
        guard FileManager.default.isReadableFile(atPath: candidate.path) else {
            throw ProjectDropError.noReadPermission(candidate.lastPathComponent)
        }

        if candidate.pathExtension == "xcworkspace" {
            let projects = workspaceProjects(at: candidate)
            guard !projects.isEmpty else {
                throw ProjectDropError.emptyDirectory(candidate.lastPathComponent)
            }
            return projects
        }

        let projects = findProjects(in: candidate, depth: 0)
        guard !projects.isEmpty else {
            throw ProjectDropError.emptyDirectory(candidate.lastPathComponent)
        }
        return projects
    }

    /// .xcworkspace → 其中引用的 .xcodeproj（排除 Pods / Carthage 等依赖工程）
    private static func workspaceProjects(at workspace: URL) -> [URL] {
        dedupe(ProjectLoader.projectURLs(inWorkspaceAt: workspace)
            .filter { !isDependencyProject($0) }
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "project.pbxproj").path) })
    }

    /// 收集候选工程：先看当前目录，再逐层下探；
    /// 同一层多个工程全部返回（交给用户选择），不再静默取第一个。
    private static func findProjects(in directory: URL, depth: Int) -> [URL] {
        guard depth <= maxSearchDepth else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        let projects = contents
            .filter { $0.pathExtension == "xcodeproj" }
            .filter { !isDependencyProject($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if !projects.isEmpty { return dedupe(projects.map(\.standardizedFileURL)) }

        // 目录里没有直接工程时，优先用 .xcworkspace 的引用表（能覆盖工程放在子目录之外的情况）
        let workspaces = contents
            .filter { $0.pathExtension == "xcworkspace" }
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "contents.xcworkspacedata").path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for workspace in workspaces {
            let resolved = workspaceProjects(at: workspace)
            if !resolved.isEmpty { return resolved }
        }

        let subdirectories = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !Self.skippedDirectoryNames.contains($0.lastPathComponent) }
            .filter { $0.pathExtension != "xcworkspace" && $0.pathExtension != "xcodeproj" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var found: [URL] = []
        for subdirectory in subdirectories {
            found.append(contentsOf: findProjects(in: subdirectory, depth: depth + 1))
        }
        return dedupe(found)
    }

    /// 依赖工程（Pods / Carthage 等）不作为用户要扫描的主工程
    private static func isDependencyProject(_ url: URL) -> Bool {
        let parentComponents = url.deletingLastPathComponent().pathComponents.suffix(3)
        if parentComponents.contains(where: { skippedDirectoryNames.contains($0) }) { return true }
        let name = url.deletingPathExtension().lastPathComponent
        return name == "Pods"
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            return seen.insert(path).inserted
        }
    }

    /// 这些目录里即使有 .xcodeproj 也不该当作「用户要扫描的工程」
    private static let skippedDirectoryNames: Set<String> = [
        "Pods", "Carthage", "DerivedData", "build", ".build", "node_modules", "fastlane",
    ]
}
