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
    /// 从 groups / build phases 列表里摘掉的 ID 引用数
    var removedReferenceCount = 0
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
        guard let decoded = Self.decode(data), !decoded.text.isEmpty else {
            throw ProjectParseError.unreadablePBXProj("空文件")
        }

        let outcomeAndText = try clean(
            pbxprojText: decoded.text,
            xcodeprojURL: xcodeprojURL,
            absolutePaths: uniquePaths
        )
        guard outcomeAndText.outcome.removedObjectCount > 0 else {
            return outcomeAndText.outcome
        }

        // 备份只保留「首次修改前」的原始文件：已存在时不覆盖，
        // 否则连续清理会把唯一的回滚点冲掉。
        let backupURL = pbxprojURL.appendingPathExtension("lumber-bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.copyItem(at: pbxprojURL, to: backupURL)
        }

        guard let outData = Self.encode(outcomeAndText.text, as: decoded) else {
            throw ProjectParseError.unreadablePBXProj("无法按原编码写回")
        }
        try outData.write(to: pbxprojURL, options: .atomic)
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

        // 与 PBXProjectGraph.build 共用同一套根目录推导，保证「清理」认定的路径与「扫描」一致
        let projectDirPath = root.string("rootObject")
            .flatMap { objects[$0]?.dictionaryValue }?
            .string("projectDirPath")
        let rootDirectory = PBXProjectGraph.rootDirectory(
            xcodeprojURL: xcodeprojURL,
            projectDirPath: projectDirPath
        )

        let resolver = PathResolver(objects: objects, rootDirectory: rootDirectory)
        let pathSet = Set(absolutePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })

        var fileRefIDs: Set<String> = []
        var resolvedPaths: Set<String> = []
        for (id, value) in objects {
            guard let dict = value.dictionaryValue,
                  dict.string("isa") == "PBXFileReference",
                  let path = resolver.resolve(id) else { continue }
            resolvedPaths.insert(path)
            if pathSet.contains(path) {
                fileRefIDs.insert(id)
            }
        }

        var outcome = PBXProjCleanOutcome()
        for path in absolutePaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            if resolvedPaths.contains(standardized) {
                if !outcome.cleanedPaths.contains(standardized) {
                    outcome.cleanedPaths.append(standardized)
                }
            } else if !outcome.skippedPaths.contains(standardized) {
                // 多条条目可能指向同一路径（如 imageset 内的多张图），跳过项也要去重，
                // 否则 restored / 计数会把同一路径算多遍
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
        var editor = PBXTextEditor(text: pbxprojText, idsToRemove: idsToRemove)
        let edited = editor.edit()
        let text = collapseEmptyCommas(in: edited.text)

        // 护栏：编辑结果必须仍能被解析，否则放弃本次清理（不写盘）
        _ = try PBXParser.parse(text)

        outcome.removedObjectCount = idsToRemove.count
        outcome.removedReferenceCount = edited.removedReferences
        return (outcome, text)
    }

    // MARK: - 编解码（按原编码写回，避免把 UTF-16 工程改写成 UTF-8）

    private struct DecodedProject {
        let text: String
        let encoding: String.Encoding
        /// 文件头的 BOM（可能为空），写回时原样补回
        let bom: Data
    }

    /// 仅依赖 BOM 判定 UTF-16：无 BOM 时无法可靠推断字节序，
    /// 而 Xcode 生成的 pbxproj 只有「UTF-8（可带 BOM）」和「带 BOM 的 UTF-16」两种形态。
    private static func decode(_ data: Data) -> DecodedProject? {
        if data.starts(with: Self.utf8BOM),
           let text = String(data: data.dropFirst(Self.utf8BOM.count), encoding: .utf8) {
            return DecodedProject(text: text, encoding: .utf8, bom: Self.utf8BOM)
        }
        if data.starts(with: Self.utf16LEBOM),
           let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return DecodedProject(text: text, encoding: .utf16LittleEndian, bom: Self.utf16LEBOM)
        }
        if data.starts(with: Self.utf16BEBOM),
           let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return DecodedProject(text: text, encoding: .utf16BigEndian, bom: Self.utf16BEBOM)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedProject(text: text, encoding: .utf8, bom: Data())
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return DecodedProject(text: text, encoding: .isoLatin1, bom: Data())
        }
        return nil
    }

    private static func encode(_ text: String, as decoded: DecodedProject) -> Data? {
        guard let body = text.data(using: decoded.encoding) else { return nil }
        return decoded.bom + body
    }

    private static let utf8BOM = Data([0xEF, 0xBB, 0xBF])
    private static let utf16LEBOM = Data([0xFF, 0xFE])
    private static let utf16BEBOM = Data([0xFE, 0xFF])

    // MARK: - 文本编辑

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
