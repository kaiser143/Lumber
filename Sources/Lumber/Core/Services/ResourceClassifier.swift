import Foundation

// MARK: - 资源类型判定
//
// 只把「可能产生冗余」的文件类型纳入候选，避免把工程里几千个无关文件塞进列表。

enum ResourceClassifier {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "pdf", "webp", "heic", "heif", "bmp", "tiff", "tif", "icns",
    ]
    private static let xibExtensions: Set<String> = ["xib", "storyboard"]
    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "metal", "intentdefinition",
    ]
    private static let otherExtensions: Set<String> = ["strings", "stringsdict"]

    static func type(for url: URL) -> ResourceType? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if xibExtensions.contains(ext) { return .xib }
        if codeExtensions.contains(ext) { return .code }
        if otherExtensions.contains(ext) { return .other }
        return nil
    }
}
