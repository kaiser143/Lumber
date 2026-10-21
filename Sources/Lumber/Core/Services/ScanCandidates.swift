import Foundation

// MARK: - 扫描候选构造
//
// 把磁盘上的文件/目录转成 ScanCandidate：决定类型、匹配键与聚合方式。
// imageset 会聚合为一条（大小求和、预览取最大图片），其余资源按文件逐条列出。

extension ScanEngine {
    static func makeItem(from candidate: ScanCandidate, verdict: ReferenceVerdict) -> ResourceItem {
        switch verdict {
        case .referenced(let reason):
            return ResourceItem(
                name: candidate.name,
                relativePath: candidate.relativePath,
                absolutePath: candidate.absolutePath,
                sizeBytes: candidate.sizeBytes,
                type: candidate.type,
                unreferenced: false,
                note: reason,
                directoryPath: candidate.directoryPath
            )
        case .uncertain(let reason):
            return ResourceItem(
                name: candidate.name,
                relativePath: candidate.relativePath,
                absolutePath: candidate.absolutePath,
                sizeBytes: candidate.sizeBytes,
                type: candidate.type,
                unreferenced: true,
                needsReview: true,
                note: reason,
                directoryPath: candidate.directoryPath
            )
        case .notInTarget(let reason):
            return ResourceItem(
                name: candidate.name,
                relativePath: candidate.relativePath,
                absolutePath: candidate.absolutePath,
                sizeBytes: candidate.sizeBytes,
                type: candidate.type,
                unreferenced: true,
                needsReview: true,
                notInTarget: true,
                note: reason,
                directoryPath: candidate.directoryPath
            )
        case .unused(let reason):
            return ResourceItem(
                name: candidate.name,
                relativePath: candidate.relativePath,
                absolutePath: candidate.absolutePath,
                sizeBytes: candidate.sizeBytes,
                type: candidate.type,
                unreferenced: true,
                note: reason,
                directoryPath: candidate.directoryPath
            )
        }
    }

    static func textCandidate(for url: URL, root: URL, size: Int, text: String?) -> ScanCandidate? {
        guard let type = ResourceClassifier.type(for: url) else { return nil }
        let relative = relativePath(of: url, in: root)
        let absolute = url.standardizedFileURL.path
        let baseName = url.deletingPathExtension().lastPathComponent
        let common = (url.lastPathComponent, relative, absolute, size)

        switch type {
        case .code:
            // 用文件里声明的类型名做匹配键：基类 / 协议不会实例化，但会被别的文件用到
            var keys = text.map(TypeDeclarationScanner.names(in:)) ?? []
            if !keys.contains(baseName) { keys.append(baseName) }
            return ScanCandidate(
                name: common.0, relativePath: common.1, absolutePath: common.2, sizeBytes: common.3,
                type: .code, directoryPath: nil, keys: keys, kind: .code
            )
        case .xib:
            return ScanCandidate(
                name: common.0, relativePath: common.1, absolutePath: common.2, sizeBytes: common.3,
                type: .xib, directoryPath: nil, keys: nameKeys(baseName), kind: .interface
            )
        case .image:
            return ScanCandidate(
                name: common.0, relativePath: common.1, absolutePath: common.2, sizeBytes: common.3,
                type: .image, directoryPath: nil, keys: imageKeys(for: url), kind: .looseImage
            )
        case .color, .data, .other:
            return ScanCandidate(
                name: common.0, relativePath: common.1, absolutePath: common.2, sizeBytes: common.3,
                type: type, directoryPath: nil, keys: nameKeys(baseName), kind: .bundled
            )
        }
    }

    /// 名字本身 + 驼峰变体
    static func nameKeys(_ name: String) -> [String] {
        var keys = [name]
        if let camel = camelKey(name) { keys.append(camel) }
        return keys
    }

    /// 散落图片的匹配键：完整文件名、去扩展名、去 @2x/@3x 变体
    static func imageKeys(for url: URL) -> [String] {
        let filename = url.lastPathComponent
        let base = url.deletingPathExtension().lastPathComponent
        var keys: Set<String> = [filename, base]
        if let at = base.lastIndex(of: "@") {
            let stripped = String(base[base.startIndex..<at])
            if stripped.count >= 2 { keys.insert(stripped) }
        }
        if let camel = camelKey(base) { keys.insert(camel) }
        return Array(keys)
    }

    /// 资源名的驼峰变体：代码生成工具（R.swift / SwiftGen）会把 icon_cell_badge 变成 iconCellBadge
    static func camelKey(_ name: String) -> String? {
        let parts = name.split(whereSeparator: { "_-. +@".contains($0) })
        guard parts.count >= 2 else { return nil }
        var result = parts[0].lowercased()
        for part in parts.dropFirst() {
            result += part.prefix(1).uppercased() + part.dropFirst()
        }
        return result == name ? nil : result
    }

    /// imageset / colorset / dataset 聚合成一条：大小取目录内文件总和，预览用其中最大的图片
    static func makeAssetCandidate(from entry: AssetEntry, relativePath: String) -> ScanCandidate? {
        guard let type = entry.kind.resourceType else { return nil }
        var keys = [entry.name]
        if let camel = camelKey(entry.name) { keys.append(camel) }
        let representative = entry.representativeURL ?? entry.url
        return ScanCandidate(
            name: entry.name,
            relativePath: relativePath,
            absolutePath: representative.standardizedFileURL.path,
            sizeBytes: entry.totalSizeBytes,
            type: type,
            directoryPath: entry.url.standardizedFileURL.path,
            keys: keys,
            kind: .asset
        )
    }

    /// 读取文本（支持 UTF-16 的 .strings），最多读前 1.5MB
    static func readText(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxIndexedBytes), !data.isEmpty else { return nil }

        if data.count >= 2 {
            let bom = [UInt8](data.prefix(2))
            if bom == [0xFF, 0xFE] || bom == [0xFE, 0xFF],
               let text = String(data: data, encoding: .utf16) {
                return text
            }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }
}
