import Foundation

// MARK: - 忽略规则匹配器
//
// 对齐 .gitignore 的常用子集：
// · 空行与 # 注释忽略
// · `!pattern` 取反（后出现的规则优先，与 git 一致）
// · 结尾 `/` 只匹配目录
// · 以 `/` 开头锚定到工程根目录
// · 含 `/` 的模式按「相对工程根目录的路径」匹配，`*` 不跨目录
// · 不含 `/` 的模式匹配任意层级的文件名/目录名
// · `**` 跨目录匹配
// · 大小写不敏感（macOS 文件系统常态）
//
// 已知限制（与 git 相同）：父目录被忽略时，无法用 `!` 把其中的文件再捞回来，
// 因为扫描器在目录层就已剪枝。

struct IgnoreRuleSet: Sendable {
    struct Rule: @unchecked Sendable {
        let pattern: String
        let isNegated: Bool
        let regex: NSRegularExpression
    }

    private let rules: [Rule]

    init(patterns: [String]) {
        var compiled: [Rule] = []
        for raw in patterns {
            guard let rule = Self.compile(raw) else { continue }
            compiled.append(rule)
        }
        rules = compiled
    }

    /// relativePath 需相对工程根目录；isDirectory 影响「只匹配目录」的规则
    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        guard !rules.isEmpty, !relativePath.isEmpty else { return false }
        let target = isDirectory ? relativePath + "/" : relativePath
        let range = NSRange(target.startIndex..<target.endIndex, in: target)

        var ignored = false
        for rule in rules where rule.regex.firstMatch(in: target, options: [], range: range) != nil {
            ignored = !rule.isNegated
        }
        return ignored
    }

    // MARK: - 编译

    private static func compile(_ raw: String) -> Rule? {
        var pattern = raw.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !pattern.hasPrefix("#") else { return nil }

        var negated = false
        if pattern.hasPrefix("!") {
            negated = true
            pattern.removeFirst()
        }
        var directoryOnly = false
        if pattern.hasSuffix("/") {
            directoryOnly = true
            pattern.removeLast()
        }
        var anchored = false
        if pattern.hasPrefix("/") {
            anchored = true
            pattern.removeFirst()
        }
        guard !pattern.isEmpty else { return nil }

        let glob = globToRegex(pattern)
        let isNameRule = !anchored && !pattern.contains("/")

        // name 规则可命中任意层级；path 规则从工程根目录开始匹配。
        // 命中目录时，其下所有内容一并命中，因此统一允许用 `/` 结尾或 `/` 之后接内容。
        let body: String
        if directoryOnly {
            body = (isNameRule ? "(?:^|.*/)" : "^") + glob + "/"
        } else {
            body = (isNameRule ? "(?:^|.*/)" : "^") + glob + "(?:/|$)"
        }

        guard let regex = try? NSRegularExpression(pattern: body, options: [.caseInsensitive]) else { return nil }
        return Rule(pattern: raw, isNegated: negated, regex: regex)
    }

    /// glob → 正则片段（`*` 不跨目录，`**` 跨目录，`?` 单字符）
    private static func globToRegex(_ pattern: String) -> String {
        var result = ""
        let chars = Array(pattern)
        var index = 0

        while index < chars.count {
            let char = chars[index]
            switch char {
            case "*":
                if index + 1 < chars.count, chars[index + 1] == "*" {
                    if index + 2 < chars.count, chars[index + 2] == "/" {
                        result += "(?:.*/)?"
                        index += 3
                        continue
                    }
                    result += ".*"
                    index += 2
                    continue
                }
                result += "[^/]*"
            case "?":
                result += "[^/]"
            case "[":
                // 字符集合原样透传，遇到非法的集合由 NSRegularExpression 编译失败兜底
                var set = "["
                var cursor = index + 1
                if cursor < chars.count, chars[cursor] == "!" { set += "^"; cursor += 1 }
                while cursor < chars.count, chars[cursor] != "]" {
                    set.append(chars[cursor])
                    cursor += 1
                }
                if cursor < chars.count {
                    set += "]"
                    result += set
                    index = cursor + 1
                    continue
                }
                result += "\\["
            case ".", "+", "(", ")", "{", "}", "^", "$", "|", "\\":
                result += "\\" + String(char)
            default:
                result.append(char)
            }
            index += 1
        }
        return result
    }
}
