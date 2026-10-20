import Foundation

// MARK: - Assets.xcassets 解析
//
// 一个 .xcassets 目录里，真正的资源单位是 *.imageset / *.dataset / *.colorset 这些目录，
// 目录名（去掉后缀）就是代码里 `imageNamed("name")` 使用的资源名。
// 本解析只读目录结构与 Contents.json，不读取图片内容。

enum AssetCatalogParser {
    static func parse(catalogURL: URL, relativePath: String) -> AssetCatalogInfo {
        var entries: [AssetEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: catalogURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return AssetCatalogInfo(url: catalogURL, relativePath: relativePath, entries: [])
        }

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard let kind = AssetEntry.Kind(rawValue: ext),
                  (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true else {
                continue
            }
            enumerator.skipDescendants()
            entries.append(AssetEntry(
                name: url.deletingPathExtension().lastPathComponent,
                kind: kind,
                url: url,
                fileNames: containedFileNames(in: url)
            ))
        }

        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return AssetCatalogInfo(url: catalogURL, relativePath: relativePath, entries: entries)
    }

    /// 目录内实际存在的文件名 + Contents.json 里登记的文件名（去重）
    private static func containedFileNames(in directory: URL) -> [String] {
        var names: Set<String> = []
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in contents where url.lastPathComponent != "Contents.json" {
            names.insert(url.lastPathComponent)
        }

        if let json = contentsJSONFileNames(in: directory) {
            names.formUnion(json)
        }
        return names.sorted()
    }

    private static func contentsJSONFileNames(in directory: URL) -> [String]? {
        let contentsURL = directory.appending(path: "Contents.json")
        guard let data = try? Data(contentsOf: contentsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var names: [String] = []
        for case let item as [String: Any] in (json["images"] as? [Any] ?? []) {
            if let filename = item["filename"] as? String { names.append(filename) }
        }
        if let filename = json["filename"] as? String { names.append(filename) }
        return names
    }
}

extension AssetEntry.Kind: CaseIterable {
    static let allCases: [AssetEntry.Kind] = [
        .imageSet, .dataSet, .colorSet, .appIconSet,
        .symbolSet, .launchImage, .imageStack, .spriteAtlas, .brandAssets,
    ]
}
