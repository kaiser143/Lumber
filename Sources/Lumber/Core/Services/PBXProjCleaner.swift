import Foundation

// MARK: - 删除文件后清理 pbxproj 引用
//
// 只移除「路径精确匹配」的 PBXFileReference 及其 PBXBuildFile，并从 groups / build phases
// 的 children / files 数组里删掉对应 ID。不碰 Assets.xcassets 内部的 imageset（它们通常
// 没有独立的 PBXFileReference），也不递归删除空组。
//
// 文本级编辑，尽量保留原文件其余内容与注释；写回前先备份为 project.pbxproj.lumber-bak。

struct PBXProjCleanOutcome: Equatable {
    /// 从 objects 里删掉的对象数（FileReference + BuildFile）
    var removedObjectCount = 0
    /// 在 pbxproj 里找到并清理了引用的绝对路径
    var cleanedPaths: [String] = []
    /// 无对应 PBXFileReference（例如 xcassets 内条目、同步文件夹散落文件）
    var skippedPaths: [String] = []
}

enum PBXProjCleaner {
    /// 从指定 .xcodeproj 的 project.pbxproj 中移除对给定绝对路径的引用。
    @discardableResult
    static func removeReferences(
        xcodeprojURL: URL,
        absolutePaths: [String]
    ) throws -> PBXProjCleanOutcome {
        let uniquePaths = Array(Set(absolutePaths.filter { !$0.isEmpty })).sorted()
        guard !uniquePaths.isEmpty else { return PBXProjCleanOutcome() }

        let pbxprojURL = xcodeprojURL.appending(path: "project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw ProjectParseError.missingPBXProj(xcodeprojURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: pbxprojURL)
        } catch {
            throw ProjectParseError.unreadablePBXProj(error.localizedDescription)
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !text.isEmpty else {
            throw ProjectParseError.unreadablePBXProj("空文件")
        }

        let outcomeAndText = try clean(pbxprojText: text, xcodeprojURL: xcodeprojURL, absolutePaths: uniquePaths)
        guard outcomeAndText.outcome.removedObjectCount > 0 else {
            return outcomeAndText.outcome
        }

        let backupURL = pbxprojURL.appendingPathExtension("lumber-bak")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: pbxprojURL, to: backupURL)
        try outcomeAndText.text.write(to: pbxprojURL, atomically: true, encoding: .utf8)
        return outcomeAndText.outcome
    }

    /// 纯函数：便于单测；不读写磁盘。
    static func clean(
        pbxprojText: String,
        xcodeprojURL: URL,
        absolutePaths: [String]
    ) throws -> (outcome: PBXProjCleanOutcome, text: String) {
        let root = try PBXParser.parse(pbxprojText)
        guard let objects = root.dictionary("objects") else {
            throw ProjectParseError.malformedPBXProj("缺少 objects 节点")
        }

        var rootDirectory = xcodeprojURL.deletingLastPathComponent()
        if let rootObjectID = root.string("rootObject"),
           let projectObject = objects[rootObjectID]?.dictionaryValue,
           let dirPath = projectObject.string("projectDirPath"),
           !dirPath.isEmpty {
            rootDirectory = rootDirectory.appending(path: dirPath)
        }
        rootDirectory = rootDirectory.standardizedFileURL

        let resolver = PathResolver(objects: objects, rootDirectory: rootDirectory)
        let pathSet = Set(absolutePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })

        var fileRefIDs: Set<String> = []
        var pathByID: [String: String] = [:]
        for (id, value) in objects {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "PBXFileReference",
                  let path = resolver.resolve(id) else { continue }
            pathByID[id] = path
            if pathSet.contains(path) {
                fileRefIDs.insert(id)
            }
        }

        var outcome = PBXProjCleanOutcome()
        for path in absolutePaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            if pathByID.values.contains(standardized) {
                if !outcome.cleanedPaths.contains(standardized) {
                    outcome.cleanedPaths.append(standardized)
                }
            } else {
                outcome.skippedPaths.append(standardized)
            }
        }

        guard !fileRefIDs.isEmpty else { return (outcome, pbxprojText) }

        var buildFileIDs: Set<String> = []
        for (id, value) in objects {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "PBXBuildFile",
                  let fileRef = dict.string("fileRef"),
                  fileRefIDs.contains(fileRef) else { continue }
            buildFileIDs.insert(id)
        }

        let idsToRemove = fileRefIDs.union(buildFileIDs)
        var edited = pbxprojText
        // 长 ID 优先，避免短 ID 误伤前缀（测试工程里用短 ID）
        for id in idsToRemove.sorted(by: { $0.count > $1.count || ($0.count == $1.count && $0 > $1) }) {
            edited = removeObjectDefinition(id: id, from: edited)
            edited = removeIDReferences(id: id, from: edited)
        }
        edited = collapseEmptyCommas(in: edited)

        outcome.removedObjectCount = idsToRemove.count
        return (outcome, edited)
    }

    // MARK: - 文本编辑

    /// 删掉 `ID /* comment */ = { ... };` 整段（支持多行，按花括号配对）
    private static func removeObjectDefinition(id: String, from text: String) -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let pattern = "(?m)^[ \\t]*\\Q\(id)\\E(?:\\s*/\\*[^*]*\\*/)?\\s*=\\s*\\{"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        guard let match = regex.firstMatch(in: text, options: [], range: full) else { return text }

        let openBrace = match.range.location + match.range.length - 1
        guard openBrace >= 0, openBrace < ns.length, ns.character(at: openBrace) == 0x7B else { return text }

        var depth = 0
        var index = openBrace
        var end = NSNotFound
        while index < ns.length {
            let ch = ns.character(at: index)
            if ch == 0x7B { depth += 1 }
            else if ch == 0x7D {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
            index += 1
        }
        guard end != NSNotFound else { return text }

        var cutEnd = end + 1
        if cutEnd < ns.length, ns.character(at: cutEnd) == 0x3B { cutEnd += 1 } // ;
        while cutEnd < ns.length {
            let ch = ns.character(at: cutEnd)
            if ch == 0x0A || ch == 0x0D { cutEnd += 1; break }
            if ch == 0x20 || ch == 0x09 { cutEnd += 1; continue }
            break
        }

        let mutable = NSMutableString(string: text)
        mutable.deleteCharacters(in: NSRange(location: match.range.location, length: cutEnd - match.range.location))
        return mutable as String
    }

    /// 从 `( ... )` 列表里去掉 `ID` / `ID /* comment */` 及相邻逗号
    private static func removeIDReferences(id: String, from text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: id)
        // 捕获前后逗号，便于整段抹掉
        let pattern = #"(,\s*)?\b"# + escaped + #"\b(?:\s*/\*[^*]*\*/)?(\s*,)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let hasLeading = match.range(at: 1).location != NSNotFound
            let hasTrailing = match.range(at: 2).location != NSNotFound
            if hasLeading && hasTrailing {
                // `, ID ,` → `,`：保留后逗号位置用前逗号替换整段为 `,`
                mutable.replaceCharacters(in: match.range, with: ",")
            } else if hasLeading {
                // `, ID` → 空
                mutable.deleteCharacters(in: match.range)
            } else if hasTrailing {
                // `ID ,` → 空
                mutable.deleteCharacters(in: match.range)
            } else {
                // 单独一项
                mutable.deleteCharacters(in: match.range)
            }
        }
        return mutable as String
    }

    private static func collapseEmptyCommas(in text: String) -> String {
        var result = text
        let replacements = [
            #"(,\s*,)+"#: ",",
            #"\(\s*,"#: "(",
            #",\s*\)"#: ")",
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }
}
