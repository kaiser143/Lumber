import Foundation

// MARK: - 偏好与最近工程持久化
//
// 与忽略规则一样落在 Application Support/Lumber/：
// · preferences.json — 扫描选项
// · recent_projects.json — 最近打开的 .xcodeproj

struct AppPreferences: Codable, Equatable {
    var includeCodeFiles: Bool = true
    var scanDepth: Int = 24
    /// 移到废纸篓后，同步清理 project.pbxproj 里的文件引用
    var cleanPbxprojOnDelete: Bool = true

    static let `default` = AppPreferences()
}

struct RecentProject: Codable, Equatable, Identifiable, Hashable {
    var id: String { path }
    /// .xcodeproj 绝对路径
    let path: String
    /// 展示名，如 DemoApp.xcodeproj
    let displayName: String
    let lastOpened: Date

    var url: URL { URL(fileURLWithPath: path) }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

enum PreferencesStore {
    static var directoryURL: URL { IgnoreRulesStore.directoryURL }

    private static var preferencesURL: URL {
        directoryURL.appending(path: "preferences.json")
    }

    private static var recentURL: URL {
        directoryURL.appending(path: "recent_projects.json")
    }

    static let maxRecentCount = 8

    // MARK: Preferences

    static func loadPreferences() -> AppPreferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let decoded = try? decoder.decode(AppPreferences.self, from: data) else {
            return .default
        }
        var prefs = decoded
        prefs.scanDepth = min(64, max(4, prefs.scanDepth))
        return prefs
    }

    static func savePreferences(_ preferences: AppPreferences) {
        var prefs = preferences
        prefs.scanDepth = min(64, max(4, prefs.scanDepth))
        writeJSON(prefs, to: preferencesURL)
    }

    // MARK: Recent projects

    static func loadRecentProjects() -> [RecentProject] {
        guard let data = try? Data(contentsOf: recentURL),
              let decoded = try? decoder.decode([RecentProject].self, from: data) else {
            return []
        }
        return decoded.filter(\.exists)
    }

    /// 把工程插到最近列表最前；同路径去重。
    @discardableResult
    static func recordRecentProject(xcodeprojURL: URL) -> [RecentProject] {
        let standardized = xcodeprojURL.standardizedFileURL
        let entry = RecentProject(
            path: standardized.path,
            displayName: standardized.lastPathComponent,
            lastOpened: Date()
        )
        var list = loadRecentProjects().filter { $0.path != entry.path }
        list.insert(entry, at: 0)
        if list.count > maxRecentCount {
            list = Array(list.prefix(maxRecentCount))
        }
        writeJSON(list, to: recentURL)
        return list
    }

    static func removeRecentProject(path: String) -> [RecentProject] {
        let list = loadRecentProjects().filter { $0.path != path }
        writeJSON(list, to: recentURL)
        return list
    }

    static func clearRecentProjects() {
        writeJSON([RecentProject](), to: recentURL)
    }

    // MARK: - IO

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[Lumber] 偏好写入失败：\(error.localizedDescription)")
        }
    }
}
