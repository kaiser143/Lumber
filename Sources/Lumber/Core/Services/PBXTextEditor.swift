import Foundation

// MARK: - pbxproj 文本编辑（单遍扫描，感知注释与字符串）

/// 旧实现用「正则逐 ID 全文件匹配 + 朴素花括号计数」：
/// · 注释 / 字符串里的 { } 会让计数错乱 → 删错范围，工程文件损坏
/// · 每个 ID 两次全文件扫描 + 一次整文件复制 → O(K × N)
/// · 无法区分「对象定义」与「列表项」，只能靠 \b 猜
/// 新实现：一次线性扫描同时完成定位与删除，注释 / 字符串区间原样保留。
struct PBXTextEditor {
    private let units: [UInt16]
    private let ids: Set<String>
    private var deletions: [Range<Int>] = []

    init(text: String, idsToRemove: Set<String>) {
        self.units = Array(text.utf16)
        self.ids = idsToRemove
    }

    struct Result {
        var text: String
        var removedDefinitions: Int
        var removedReferences: Int
    }

    mutating func edit() -> Result {
        var index = 0
        var definitions = 0
        var references = 0

        while index < units.count {
            let c = units[index]
            if Self.isWhitespace(c) { index += 1; continue }
            if c == Self.slash, index + 1 < units.count {
                if units[index + 1] == Self.star { index = endOfBlockComment(from: index); continue }
                if units[index + 1] == Self.slash { index = endOfLineComment(from: index); continue }
            }
            if c == Self.quote { index = endOfString(from: index); continue }
            if Self.isDelimiter(c) { index += 1; continue }

            let token = tokenRange(from: index)
            guard token.upperBound > token.lowerBound else { index += 1; continue }
            index = token.upperBound
            guard ids.contains(Self.string(units[token])) else { continue }

            if let range = objectDefinitionRange(forTokenAt: token) {
                deletions.append(range)
                definitions += 1
                index = range.upperBound          // 跳过整个对象体，避免重复处理
            } else if let range = listItemRange(forTokenAt: token) {
                deletions.append(range)
                references += 1
            }
        }
        return Result(text: applyingDeletions(), removedDefinitions: definitions, removedReferences: references)
    }

    // MARK: - 删除区间定位

    /// `ID /* name */ = { ... };` → 连同缩进与行尾换行一起删除
    private func objectDefinitionRange(forTokenAt token: Range<Int>) -> Range<Int>? {
        var cursor = skipTrivia(from: token.upperBound)
        guard cursor < units.count, units[cursor] == Self.equals else { return nil }
        cursor = skipTrivia(from: cursor + 1)
        guard cursor < units.count, units[cursor] == Self.lbrace else { return nil }
        guard let close = matchingBrace(from: cursor) else { return nil }

        var end = close + 1
        if end < units.count, units[end] == Self.semicolon { end += 1 }
        while end < units.count, units[end] == Self.space || units[end] == Self.tab { end += 1 }
        if end < units.count, units[end] == Self.lf || units[end] == Self.cr { end += 1 }

        var start = token.lowerBound
        while start > 0, units[start - 1] == Self.space || units[start - 1] == Self.tab { start -= 1 }
        return start..<end
    }

    /// `(A, ID /* c */, B)` → 删除 ID 与其后注释，并吃掉相邻的一个逗号
    ///
    /// 列表里只有一项（`children = (ID);`）或手写省略尾逗号时，前方没有逗号；
    /// 这时必须回看左括号才能确认它是列表项，否则会留下指向已删对象的悬空引用。
    private func listItemRange(forTokenAt token: Range<Int>) -> Range<Int>? {
        var end = skipTrivia(from: token.upperBound)     // 吃掉 ID 后面的 /* comment */
        var start = token.lowerBound
        if end < units.count, units[end] == Self.comma {
            end += 1
        } else {
            // 回看要跨过换行：Xcode 写出的列表是一行一项，前一项的分隔符在上一行行尾
            var cursor = start - 1
            while cursor >= 0, Self.isWhitespace(units[cursor]) { cursor -= 1 }
            guard cursor >= 0 else { return nil }
            // 非列表项（如 `fileRef = X;`）不删
            guard units[cursor] == Self.comma || units[cursor] == Self.lparen else { return nil }
            if units[cursor] == Self.comma { start = cursor }
        }
        return start..<end
    }

    // MARK: - 扫描原语

    private func matchingBrace(from openBrace: Int) -> Int? {
        var depth = 0
        var index = openBrace
        while index < units.count {
            let c = units[index]
            if Self.isWhitespace(c) { index += 1; continue }
            if c == Self.slash, index + 1 < units.count {
                if units[index + 1] == Self.star { index = endOfBlockComment(from: index); continue }
                if units[index + 1] == Self.slash { index = endOfLineComment(from: index); continue }
            }
            if c == Self.quote { index = endOfString(from: index); continue }
            if c == Self.lbrace { depth += 1; index += 1; continue }
            if c == Self.rbrace {
                depth -= 1
                if depth == 0 { return index }
                index += 1
                continue
            }
            index += 1
        }
        return nil
    }

    private func skipTrivia(from start: Int) -> Int {
        var index = start
        while index < units.count {
            let c = units[index]
            if Self.isWhitespace(c) { index += 1; continue }
            if c == Self.slash, index + 1 < units.count {
                if units[index + 1] == Self.star { index = endOfBlockComment(from: index); continue }
                if units[index + 1] == Self.slash { index = endOfLineComment(from: index); continue }
            }
            return index
        }
        return index
    }

    private func tokenRange(from start: Int) -> Range<Int> {
        var index = start
        while index < units.count {
            let c = units[index]
            if Self.isWhitespace(c) || Self.isDelimiter(c) || c == Self.quote { break }
            if c == Self.slash, index + 1 < units.count,
               units[index + 1] == Self.star || units[index + 1] == Self.slash { break }
            index += 1
        }
        return start..<index
    }

    private func endOfBlockComment(from start: Int) -> Int {
        var index = start + 2
        while index + 1 < units.count {
            if units[index] == Self.star, units[index + 1] == Self.slash { return index + 2 }
            index += 1
        }
        return units.count
    }

    private func endOfLineComment(from start: Int) -> Int {
        var index = start + 2
        while index < units.count, units[index] != Self.lf, units[index] != Self.cr { index += 1 }
        return index
    }

    private func endOfString(from start: Int) -> Int {
        var index = start + 1
        while index < units.count {
            if units[index] == Self.backslash { index += 2; continue }
            if units[index] == Self.quote { return index + 1 }
            index += 1
        }
        return units.count
    }

    // MARK: - 应用删除（区间合并后单次拼接）

    private func applyingDeletions() -> String {
        guard !deletions.isEmpty else { return Self.string(units[...]) }
        var kept: [UInt16] = []
        kept.reserveCapacity(units.count)
        var cursor = 0
        for range in mergedDeletions() {
            if range.lowerBound > cursor { kept.append(contentsOf: units[cursor..<range.lowerBound]) }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < units.count { kept.append(contentsOf: units[cursor...]) }
        return Self.string(kept[...])
    }

    private func mergedDeletions() -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in deletions.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.indices.last, range.lowerBound <= result[last].upperBound {
                result[last] = result[last].lowerBound..<max(result[last].upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    // MARK: - 常量

    private static let slash: UInt16 = 0x2F, star: UInt16 = 0x2A, quote: UInt16 = 0x22
    private static let backslash: UInt16 = 0x5C, lbrace: UInt16 = 0x7B, rbrace: UInt16 = 0x7D
    private static let lparen: UInt16 = 0x28, rparen: UInt16 = 0x29, equals: UInt16 = 0x3D
    private static let semicolon: UInt16 = 0x3B, comma: UInt16 = 0x2C
    private static let space: UInt16 = 0x20, tab: UInt16 = 0x09
    private static let lf: UInt16 = 0x0A, cr: UInt16 = 0x0D

    private static func isWhitespace(_ c: UInt16) -> Bool { c == space || c == tab || c == lf || c == cr }
    private static func isDelimiter(_ c: UInt16) -> Bool {
        c == lbrace || c == rbrace || c == lparen || c == rparen
            || c == equals || c == semicolon || c == comma
    }
    private static func string<C: Collection>(_ units: C) -> String where C.Element == UInt16 {
        String(decoding: units, as: UTF16.self)
    }
}
