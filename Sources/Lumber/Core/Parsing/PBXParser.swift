import Foundation

// MARK: - pbxproj 语法分析
//
// 把 project.pbxproj 解析成 PBXValue 字典树。
// 只做语法层还原，不解释语义（语义在 PBXProjectGraph）。

enum PBXParser {
    static func parse(_ text: String) throws -> [String: PBXValue] {
        var tokenizer = PBXTokenizer(text)
        var tokens: [PBXToken] = []
        while let token = try tokenizer.next() {
            tokens.append(token)
        }
        var stream = TokenStream(tokens: tokens)
        return try stream.parseDictionary()
    }
}

private struct TokenStream {
    let tokens: [PBXToken]
    var index = 0

    var current: PBXToken? { index < tokens.count ? tokens[index] : nil }

    mutating func advance() -> PBXToken? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    mutating func parseDictionary() throws -> [String: PBXValue] {
        try expect(.leftBrace)
        var result: [String: PBXValue] = [:]
        while true {
            guard let token = current else {
                throw PBXSyntaxError(message: "字典未闭合", offset: index)
            }
            if token == .rightBrace {
                index += 1
                return result
            }
            guard case .string(let key) = token else {
                throw PBXSyntaxError(message: "期望字典键", offset: index)
            }
            index += 1
            try expect(.equals)
            let value = try parseValue()
            if current == .semicolon { index += 1 }
            result[key] = value
        }
    }

    private mutating func parseArray() throws -> [PBXValue] {
        try expect(.leftParen)
        var result: [PBXValue] = []
        while true {
            guard let token = current else {
                throw PBXSyntaxError(message: "数组未闭合", offset: index)
            }
            if token == .rightParen {
                index += 1
                return result
            }
            result.append(try parseValue())
            if current == .comma {
                index += 1
            } else if current != .rightParen {
                throw PBXSyntaxError(message: "数组元素之间缺少逗号", offset: index)
            }
        }
    }

    private mutating func parseValue() throws -> PBXValue {
        guard let token = current else {
            throw PBXSyntaxError(message: "缺少值", offset: index)
        }
        switch token {
        case .leftBrace:
            return .dictionary(try parseDictionary())
        case .leftParen:
            return .array(try parseArray())
        case .string(let value):
            index += 1
            return .string(value)
        default:
            throw PBXSyntaxError(message: "意外的符号", offset: index)
        }
    }

    private mutating func expect(_ token: PBXToken) throws {
        guard current == token else {
            throw PBXSyntaxError(message: "期望符号 \(token)", offset: index)
        }
        index += 1
    }
}
