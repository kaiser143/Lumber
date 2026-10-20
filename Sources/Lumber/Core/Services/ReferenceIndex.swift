import Foundation

// MARK: - 文本 token 哈希
//
// 引用判定不需要保存原文，只要判断「某个名字是否在工程文本里出现过」，
// 因此索引里只存 token 的 64 位 FNV-1a 哈希，内存占用与工程大小线性相关但不含字符串开销。

enum TokenHasher {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    @inline(__always)
    static func hash<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var result = offsetBasis
        for byte in bytes {
            result = (result ^ UInt64(byte)) &* prime
        }
        return result
    }

    /// 一个 token 及其派生形式：整串、按点号切开的每一段
    /// （`R.image.foo_bar` 这种成员访问链里，真正的资源名是最后一段）
    static func derivedHashes(of buffer: [UInt8]) -> [UInt64] {
        var hashes: [UInt64] = [hash(buffer)]
        var start = 0
        for index in 0..<buffer.count where buffer[index] == UInt8(ascii: ".") {
            if index - start >= 2 { hashes.append(hash(buffer[start..<index])) }
            start = index + 1
        }
        if buffer.count - start >= 2 {
            hashes.append(hash(buffer[start...]))
        }
        return hashes
    }

    /// token 字符：ASCII 字母数字 + `_ - + @ .`，非 ASCII（中文文件名等）一律视为 token 字符
    ///
    /// 例外是中日韩标点与全角符号：它们只能当分隔符，否则「参考 OrphanView，已废弃」
    /// 会被切成一个 token，注释里提到的类型名就再也配对不上了。
    @inline(__always)
    static func isTokenScalar(_ value: UInt32) -> Bool {
        if value < 128 {
            switch value {
            case 48...57, 65...90, 97...122: return true
            case 95, 45, 43, 64, 46: return true
            default: return false
            }
        }
        switch value {
        case 0x3000...0x303F, 0xFF01...0xFF0F, 0xFF1A...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65:
            return false
        default:
            return true
        }
    }
}

// MARK: - 引用索引
//
// loose：包含注释在内的全部 token
// strict：剔除注释后的 token（字符串字面量算代码）
//
// 只有 strict 命中才算「真引用」；仅 loose 命中说明名字只出现在注释/说明里，需要人工确认。

struct ReferenceIndex: Sendable {
    fileprivate let strict: Set<UInt64>
    fileprivate let loose: Set<UInt64>
    /// token → 出现过它的文件数量。用于区分「只在本文件里出现」与「被别的文件用到」
    fileprivate let strictDocumentCounts: [UInt64: UInt16]
    fileprivate let looseDocumentCounts: [UInt64: UInt16]

    var tokenCount: Int { strict.count }

    func containsStrict(_ key: String) -> Bool {
        strict.contains(Self.hash(key))
    }

    func containsLoose(_ key: String) -> Bool {
        loose.contains(Self.hash(key))
    }

    func containsStrict(anyOf keys: [String]) -> Bool {
        keys.contains { containsStrict($0) }
    }

    func containsLoose(anyOf keys: [String]) -> Bool {
        keys.contains { containsLoose($0) }
    }

    /// 该名字是否出现在**另一个**文件里
    ///
    /// 只统计 strict（剔除注释），并且要求至少两个不同文件命中：
    /// 声明本身一定占掉其中一个，剩下那次才是「被别人用到」。
    func isUsedInOtherDocuments(_ key: String) -> Bool {
        (strictDocumentCounts[Self.hash(key)] ?? 0) >= 2
    }

    func isUsedInOtherDocuments(anyOf keys: [String]) -> Bool {
        keys.contains { isUsedInOtherDocuments($0) }
    }

    /// 该名字是否只在**别的文件**的注释里被提到过
    func isMentionedInOtherDocuments(_ key: String) -> Bool {
        (looseDocumentCounts[Self.hash(key)] ?? 0) >= 2
    }

    func isMentionedInOtherDocuments(anyOf keys: [String]) -> Bool {
        keys.contains { isMentionedInOtherDocuments($0) }
    }

    private static func hash(_ key: String) -> UInt64 {
        TokenHasher.hash(Array(key.lowercased().utf8))
    }
}

// MARK: - 索引构建

struct ReferenceIndexBuilder {
    private var strict: Set<UInt64> = []
    private var loose: Set<UInt64> = []
    private var strictDocumentCounts: [UInt64: UInt16] = [:]
    private var looseDocumentCounts: [UInt64: UInt16] = [:]
    /// 当前文件已登记的 token（同一个 token 在一个文件里只计一次文档数）
    private var currentStrictTokens: Set<UInt64> = []
    private var currentLooseTokens: Set<UInt64> = []
    private var stringDelimiter: Unicode.Scalar = "\""
    private var buffer: [UInt8] = []
    private var bufferOverflow = false

    /// 单文件最多索引的字符数（1MB 左右），避免超大文件拖慢扫描
    static let maxIndexedLength = 1_200_000

    mutating func addText(_ text: String) {
        currentStrictTokens.removeAll(keepingCapacity: true)
        currentLooseTokens.removeAll(keepingCapacity: true)
        let source = text.count > Self.maxIndexedLength
            ? String(text.prefix(Self.maxIndexedLength))
            : text
        let scalars = Array(source.unicodeScalars)
        var mode: Mode = .normal
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil

            switch mode {
            case .normal:
                if scalar == "/", next == "/" {
                    flush(intoStrict: true)
                    mode = .lineComment
                    index += 2
                    continue
                }
                if scalar == "/", next == "*" {
                    flush(intoStrict: true)
                    mode = .blockComment
                    index += 2
                    continue
                }
                if scalar == "<", next == "!", index + 3 < scalars.count,
                   scalars[index + 2] == "-", scalars[index + 3] == "-" {
                    flush(intoStrict: true)
                    mode = .xmlComment
                    index += 4
                    continue
                }
                if scalar == "\"" || scalar == "'" {
                    flush(intoStrict: true)
                    stringDelimiter = scalar
                    mode = .string
                    index += 1
                    continue
                }
                consume(scalar, intoStrict: true)

            case .string:
                if scalar == "\\" {
                    index += 2
                    continue
                }
                if scalar == stringDelimiter {
                    flush(intoStrict: true)
                    mode = .normal
                    index += 1
                    continue
                }
                consume(scalar, intoStrict: true)

            case .lineComment:
                if scalar == "\n" || scalar == "\r" {
                    flush(intoStrict: false)
                    mode = .normal
                } else {
                    consume(scalar, intoStrict: false)
                }

            case .blockComment:
                if scalar == "*", next == "/" {
                    flush(intoStrict: false)
                    mode = .normal
                    index += 2
                    continue
                }
                consume(scalar, intoStrict: false)

            case .xmlComment:
                if scalar == "-", next == "-", index + 2 < scalars.count, scalars[index + 2] == ">" {
                    flush(intoStrict: false)
                    mode = .normal
                    index += 3
                    continue
                }
                consume(scalar, intoStrict: false)
            }

            index += 1
        }
        flush(intoStrict: mode == .normal || mode == .string)
    }

    func build() -> ReferenceIndex {
        ReferenceIndex(
            strict: strict,
            loose: loose,
            strictDocumentCounts: strictDocumentCounts,
            looseDocumentCounts: looseDocumentCounts
        )
    }

    // MARK: - 私有

    private enum Mode {
        case normal
        case string
        case lineComment
        case blockComment
        case xmlComment
    }

    private mutating func consume(_ scalar: Unicode.Scalar, intoStrict: Bool) {
        guard TokenHasher.isTokenScalar(scalar.value) else {
            flush(intoStrict: intoStrict)
            return
        }
        guard buffer.count < 96 else {
            bufferOverflow = true
            return
        }
        if scalar.value < 128 {
            let byte = UInt8(scalar.value)
            buffer.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
        } else {
            for byte in String(scalar).utf8 { buffer.append(byte) }
        }
    }

    private mutating func flush(intoStrict: Bool) {
        defer {
            buffer.removeAll(keepingCapacity: true)
            bufferOverflow = false
        }
        guard !bufferOverflow, buffer.count >= 2 else { return }
        let hashes = TokenHasher.derivedHashes(of: buffer)
        loose.formUnion(hashes)
        for hash in hashes where currentLooseTokens.insert(hash).inserted {
            Self.bump(&looseDocumentCounts, hash)
        }
        guard intoStrict else { return }
        strict.formUnion(hashes)
        for hash in hashes where currentStrictTokens.insert(hash).inserted {
            Self.bump(&strictDocumentCounts, hash)
        }
    }

    private static func bump(_ counts: inout [UInt64: UInt16], _ hash: UInt64) {
        if counts[hash, default: 0] < UInt16.max {
            counts[hash, default: 0] += 1
        }
    }
}
