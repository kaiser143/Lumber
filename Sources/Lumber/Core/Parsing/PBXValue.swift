import Foundation

// MARK: - pbxproj 值模型
//
// project.pbxproj 是 OpenStep 风格的 plist：只有字典、数组与字符串三种值。
// 这里用一个极简的间接枚举承载解析结果，再由 PBXProjectGraph 解释语义。

indirect enum PBXValue: Equatable {
    case string(String)
    case array([PBXValue])
    case dictionary([String: PBXValue])

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var arrayValue: [PBXValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var dictionaryValue: [String: PBXValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> PBXValue? {
        dictionaryValue?[key]
    }
}

// MARK: - 便捷读取

extension Dictionary where Key == String, Value == PBXValue {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func strings(_ key: String) -> [String] {
        self[key]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    func dictionary(_ key: String) -> [String: PBXValue]? {
        self[key]?.dictionaryValue
    }
}

// MARK: - 语法错误

struct PBXSyntaxError: LocalizedError {
    let message: String
    let offset: Int

    var errorDescription: String? { "\(message)（偏移 \(offset)）" }
}

// MARK: - 词法分析
//
// 支持的语法元素：{ } ( ) = ; , 字符串（带引号/裸串）、
// 注释 /* ... */ 与 // 行注释（pbxproj 里大量使用 /* comment */ 标注对象名）。

enum PBXToken: Equatable {
    case leftBrace
    case rightBrace
    case leftParen
    case rightParen
    case equals
    case semicolon
    case comma
    case string(String)
}

struct PBXTokenizer {
    private let scalars: [UnicodeScalar]
    private var index: Int = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    mutating func next() throws -> PBXToken? {
        try skipTrivia()
        guard index < scalars.count else { return nil }
        let scalar = scalars[index]
        switch scalar {
        case "{": index += 1; return .leftBrace
        case "}": index += 1; return .rightBrace
        case "(": index += 1; return .leftParen
        case ")": index += 1; return .rightParen
        case "=": index += 1; return .equals
        case ";": index += 1; return .semicolon
        case ",": index += 1; return .comma
        case "\"": return .string(try readQuoted())
        default: return .string(try readBare())
        }
    }

    /// 跳过空白、块注释与行注释
    private mutating func skipTrivia() throws {
        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                index += 1
                continue
            }
            if scalar == "/", index + 1 < scalars.count {
                let nextScalar = scalars[index + 1]
                if nextScalar == "*" {
                    try skipBlockComment()
                    continue
                }
                if nextScalar == "/" {
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                    continue
                }
            }
            return
        }
    }

    private mutating func skipBlockComment() throws {
        let start = index
        index += 2
        while index + 1 < scalars.count {
            if scalars[index] == "*", scalars[index + 1] == "/" {
                index += 2
                return
            }
            index += 1
        }
        throw PBXSyntaxError(message: "块注释未闭合", offset: start)
    }

    /// 带引号字符串：支持 \" \\ \n \t \U 转义
    private mutating func readQuoted() throws -> String {
        let start = index
        index += 1
        var result = String.UnicodeScalarView()
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\" {
                index += 1
                guard index < scalars.count else { break }
                let escaped = scalars[index]
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "0": result.append(UnicodeScalar(0))
                default: result.append(escaped)
                }
                index += 1
                continue
            }
            if scalar == "\"" {
                index += 1
                return String(result)
            }
            result.append(scalar)
            index += 1
        }
        throw PBXSyntaxError(message: "字符串未闭合", offset: start)
    }

    /// 裸串：读到空白或分隔符为止（路径里可能包含 / . - 等字符）
    private mutating func readBare() throws -> String {
        var result = String.UnicodeScalarView()
        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
            if "{}()=;,\"".unicodeScalars.contains(scalar) { break }
            if scalar == "/", index + 1 < scalars.count,
               scalars[index + 1] == "*" || scalars[index + 1] == "/" {
                break
            }
            result.append(scalar)
            index += 1
        }
        guard !result.isEmpty else {
            throw PBXSyntaxError(message: "遇到无法识别的字符", offset: index)
        }
        return String(result)
    }
}
