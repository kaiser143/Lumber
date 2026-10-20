import Foundation

// MARK: - 拖放目标校验
//
// 把用户拖入 / 选择的东西规整成一个可解析的 .xcodeproj 目录：
// · .xcodeproj（目录）           → 直接通过
// · 普通目录                     → 在其中查找第一个 .xcodeproj
// · 其它文件                     → 抛错，由界面在拖放区提示

enum ProjectResolver {
    /// 目录递归查找的最大层数，避免在大仓库里全盘遍历
    private static let maxSearchDepth = 4

    static func resolve(_ url: URL) throws -> URL {
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
            return candidate
        }

        guard isDirectory.boolValue else {
            throw ProjectDropError.unsupportedType(candidate.lastPathComponent)
        }
        guard FileManager.default.isReadableFile(atPath: candidate.path) else {
            throw ProjectDropError.noReadPermission(candidate.lastPathComponent)
        }

        if let found = findXcodeproj(in: candidate, depth: 0) {
            return found
        }
        throw ProjectDropError.emptyDirectory(candidate.lastPathComponent)
    }

    /// 广度优先找第一个 .xcodeproj：先看当前目录，再逐层下探
    private static func findXcodeproj(in directory: URL, depth: Int) -> URL? {
        guard depth <= maxSearchDepth else { return nil }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        let projects = contents
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if let first = projects.first { return first.standardizedFileURL }

        let subdirectories = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !Self.skippedDirectoryNames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for subdirectory in subdirectories {
            if let found = findXcodeproj(in: subdirectory, depth: depth + 1) { return found }
        }
        return nil
    }

    /// 这些目录里即使有 .xcodeproj 也不该当作「用户要扫描的工程」
    private static let skippedDirectoryNames: Set<String> = [
        "Pods", "Carthage", "DerivedData", "build", ".build", "node_modules", "fastlane",
    ]
}
