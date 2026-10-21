import AppKit
import ImageIO

// MARK: - 磁盘图片加载
//
// 列表缩略图与预览大图都从这里取：用 ImageIO 直接解码到目标尺寸，
// 避免把几百 MB 的工程原图整张读进内存。

/// NSCache 本身线程安全，单独抽出来放在 actor 之外，
/// 让列表视图能在主线程同步命中缓存（滚动复用 cell 时立即出图，不闪空白）。
private final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    let images = NSCache<NSString, NSImage>()

    private init() {
        images.countLimit = 400
        // 预览大图按 2400px 解码，单张可达数十 MB；只限条数会在浏览大量工程时堆出上 GB 内存
        images.totalCostLimit = 256 * 1024 * 1024
    }
}

actor ImageStore {
    static let shared = ImageStore()

    private let cache = ImageCache.shared.images

    /// 列表缩略图
    func thumbnail(for item: ResourceItem, maxPixel: CGFloat = 120) async -> NSImage? {
        guard !item.absolutePath.isEmpty else { return nil }
        return await image(at: item.absolutePath, maxPixel: maxPixel)
    }

    /// 预览大图（先按屏幕可视尺寸解码，避免超大图卡顿）
    func preview(for item: ResourceItem, maxPixel: CGFloat = 2400) async -> NSImage? {
        guard !item.absolutePath.isEmpty else { return nil }
        return await image(at: item.absolutePath, maxPixel: maxPixel)
    }

    /// 同步查询已解码好的缩略图（未命中返回 nil，调用方再走异步加载）
    nonisolated func cachedThumbnail(for item: ResourceItem, maxPixel: CGFloat = 120) -> NSImage? {
        guard !item.absolutePath.isEmpty else { return nil }
        return ImageCache.shared.images.object(forKey: Self.cacheKey(path: item.absolutePath, maxPixel: maxPixel))
    }

    func image(at path: String, maxPixel: CGFloat) async -> NSImage? {
        let key = Self.cacheKey(path: path, maxPixel: maxPixel)
        if let cached = cache.object(forKey: key) { return cached }

        let image = Self.decode(path: path, maxPixel: maxPixel)
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    private nonisolated static func cacheKey(path: String, maxPixel: CGFloat) -> NSString {
        "\(path)|\(Int(maxPixel))" as NSString
    }

    private static func decode(path: String, maxPixel: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        // 矢量图（SVG）/ PDF 等 ImageIO 缩略图不支持的格式回退到 NSImage
        return NSImage(contentsOf: url)
    }
}

// MARK: - 文本文件读取（代码 / XIB / Storyboard 预览）

enum TextFileLoader {
    /// 预览时最多读取的字节数，超出部分截断（防止误读超大文件卡界面）
    static let maxPreviewBytes = 400_000

    static func read(at path: String) -> String? {
        guard !path.isEmpty,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxPreviewBytes) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func modificationDate(at path: String) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
}
