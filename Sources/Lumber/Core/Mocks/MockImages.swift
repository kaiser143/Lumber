import AppKit

// MARK: - 程序生成的示例图（仅 --mock 调试时使用，不读磁盘）

/// 为「图片」类型 Mock 条目生成确定性渐变缩略图，
/// 以及首页中央的拟物深色 App 图标（对标图2）。
final class MockImages {
    static let shared = MockImages()
    private var cache: [String: NSImage] = [:]

    private init() {}

    func thumbnail(for item: ResourceItem) -> NSImage? {
        guard item.type == .image else { return nil }
        if let cached = cache[item.id.uuidString] { return cached }
        let image = Self.gradientImage(seed: abs(item.name.hashValue), size: NSSize(width: 120, height: 120))
        cache[item.id.uuidString] = image
        return image
    }

    /// 大图预览用：同一种子、更大尺寸
    func preview(for item: ResourceItem) -> NSImage? {
        guard item.type == .image else { return nil }
        return Self.gradientImage(seed: abs(item.name.hashValue), size: NSSize(width: 640, height: 480))
    }

    /// 首页拟物 App 图标（深色圆角 + 中央旋钮 + 图片卡片）
    var appEmblem: NSImage {
        if let cached = cache["__emblem__"] { return cached }
        let size = NSSize(width: 208, height: 208)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        // 深色圆角底
        let path = CGPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)),
                          cornerWidth: 46, cornerHeight: 46, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let bg = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1),
                     CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)] as CFArray,
            locations: [0, 1]
        )
        ctx.drawLinearGradient(bg!, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])

        // 顶部小指示灯
        dot(ctx, x: 52, y: 150, color: CGColor(red: 0.55, green: 0.9, blue: 0.55, alpha: 1))
        dot(ctx, x: 156, y: 150, color: CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
        ("LUMB" as NSString).draw(
            at: NSPoint(x: 78, y: 142),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor(white: 0.98, alpha: 1),
            ]
        )

        // 中央旋钮
        let knob = CGRect(x: 84, y: 118, width: 40, height: 40)
        ctx.setFillColor(CGColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1))
        ctx.fillEllipse(in: knob)
        ctx.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.33, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 92, y: 126, width: 24, height: 24))
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
        ctx.setLineWidth(2)
        ctx.strokeLineSegments(between: [CGPoint(x: 104, y: 126), CGPoint(x: 104, y: 140)])

        // 出纸槽
        ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1))
        ctx.fill(CGRect(x: 40, y: 92, width: 128, height: 14))

        // 弹出的图片卡片
        let card = CGRect(x: 58, y: 34, width: 92, height: 62)
        ctx.setFillColor(CGColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1))
        ctx.addPath(card.rounded(radius: 6))
        ctx.fillPath()
        // 卡片里的山水简笔画
        ctx.setFillColor(CGColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 1))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 58, y: 34))
        ctx.addLine(to: CGPoint(x: 84, y: 72))
        ctx.addLine(to: CGPoint(x: 104, y: 50))
        ctx.addLine(to: CGPoint(x: 122, y: 70))
        ctx.addLine(to: CGPoint(x: 150, y: 34))
        ctx.closePath()
        ctx.fillPath()
        ctx.setFillColor(CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 118, y: 68, width: 12, height: 12))

        image.unlockFocus()
        cache["__emblem__"] = image
        return image
    }

    private func dot(_ ctx: CGContext, x: CGFloat, y: CGFloat, color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
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

private extension CGRect {
    func rounded(radius: CGFloat) -> CGPath {
        CGPath(roundedRect: self, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
