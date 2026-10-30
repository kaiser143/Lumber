import AppKit

// MARK: - 程序生成的示例图（仅 --mock 调试时使用，不读磁盘）

/// 为「图片」类型 Mock 条目生成确定性渐变缩略图与预览大图。
///
/// 单例，且缩略图缓存可能被列表（缩略图）与预览窗口并发读写，因此用锁保护后声明 Sendable。
final class MockImages: @unchecked Sendable {
    static let shared = MockImages()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    private init() {}

    func thumbnail(for item: ResourceItem) -> NSImage? {
        guard item.type == .image else { return nil }
        let key = item.id.uuidString
        lock.lock()
        let hit = cache[key]
        lock.unlock()
        if let hit { return hit }

        let image = Self.gradientImage(seed: abs(item.name.hashValue), size: NSSize(width: 120, height: 120))
        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }

    /// 大图预览用：同一种子、更大尺寸
    func preview(for item: ResourceItem) -> NSImage? {
        guard item.type == .image else { return nil }
        return Self.gradientImage(seed: abs(item.name.hashValue), size: NSSize(width: 640, height: 480))
    }

    private static func gradientImage(seed: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.55, 0.45, 0.95), (0.95, 0.45, 0.62), (0.35, 0.75, 0.65),
            (0.98, 0.72, 0.30), (0.38, 0.62, 0.96), (0.72, 0.48, 0.90),
        ]
        let first = palette[seed % palette.count]
        let second = palette[(seed / 7 + 2) % palette.count]
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: first.0, green: first.1, blue: first.2, alpha: 1),
                     CGColor(red: second.0, green: second.1, blue: second.2, alpha: 1)] as CFArray,
            locations: [0, 1]
        )
        ctx.drawLinearGradient(
            gradient!,
            start: CGPoint(x: 0, y: size.height),
            end: CGPoint(x: size.width, y: 0),
            options: []
        )
        // 白色山形剪影，营造「图片」观感
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: 0))
        ctx.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.55))
        ctx.addLine(to: CGPoint(x: size.width * 0.55, y: size.height * 0.3))
        ctx.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.5))
        ctx.addLine(to: CGPoint(x: size.width, y: size.height * 0.18))
        ctx.addLine(to: CGPoint(x: size.width, y: 0))
        ctx.closePath()
        ctx.fillPath()
        image.unlockFocus()
        return image
    }
}
