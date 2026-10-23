import Foundation

// MARK: - 忽略规则持久化
//
// 用户规则写入 ~/Library/Application Support/Lumber/ignore_rules（每行一条，允许 # 注释）。
// 扫描选项与最近工程见 PreferencesStore。

enum IgnoreRulesStore {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "Lumber", directoryHint: .isDirectory)
    }

    static var fileURL: URL {
        directoryURL.appending(path: "ignore_rules")
    }

    static var displayPath: String {
        (fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    /// 读取用户规则（已剔除空行与注释）
    static func loadPatterns() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return normalize(text)
    }

    /// 保存用户规则（自动去重）
    static func save(_ patterns: [String]) {
        let unique = deduplicated(patterns)
        let header = "# Lumber 忽略规则（每行一条，语法对齐 .gitignore 常用子集）\n"
        let body = unique.joined(separator: "\n") + (unique.isEmpty ? "" : "\n")
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try (header + body).write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[Lumber] 忽略规则保存失败：\(error.localizedDescription)")
        }
    }

    /// 从 .gitignore 文件解析规则（可直接复用文本解析）
    static func patterns(inGitignoreAt url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return deduplicated(normalize(text))
    }

    private static func normalize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func deduplicated(_ patterns: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for pattern in patterns where seen.insert(pattern).inserted {
            result.append(pattern)
        }
        return result
    }
}
