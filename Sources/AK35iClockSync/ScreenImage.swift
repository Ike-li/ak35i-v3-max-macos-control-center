import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum ScreenImageError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "无法读取图片；支持 PNG、JPEG、GIF 等 macOS 能打开的格式。"
    }
}

/// Converts pictures into 240 × 135 screen frames, scaled to fit on black.
enum ScreenImage {
    /// Browsers also treat a GIF delay of 0 as 100 ms.
    static let defaultDelay = 100

    static func frames(from data: Data) throws -> [ScreenFrame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw ScreenImageError.unreadable
        }
        return try (0..<CGImageSourceGetCount(source)).map { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw ScreenImageError.unreadable }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let seconds = (gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]) as? Double ?? 0
            let delay = Int((seconds * 1000).rounded())
            return frame(from: image, delay: delay > 0 ? delay : defaultDelay)
        }
    }

    static func frame(from image: CGImage, delay: Int) -> ScreenFrame {
        render { context, bounds in
            let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }.withDelay(delay)
    }

    /// Rainbow from left to right, white square top left, black square bottom
    /// right and a caption, so orientation and colour order can be checked.
    static func testPattern() -> ScreenFrame {
        render { context, bounds in
            for x in 0..<ScreenProtocol.width {
                context.setFillColor(RGBColor(hue: Double(x) / Double(ScreenProtocol.width) * 0.8).cgColor)
                context.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: bounds.height))
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: bounds.height - 20, width: 20, height: 20))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: bounds.width - 20, y: 0, width: 20, height: 20))

            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 24, nil)!
            let text = NSAttributedString(string: "AK35i macOS", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(text)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: (bounds.width - width) / 2, y: bounds.height / 2 - 8)
            CTLineDraw(line, context)
        }.withDelay(defaultDelay)
    }

    /// Draws on an opaque black 240 × 135 sRGB canvas and reads it back row by
    /// row from the top.
    private static func render(_ draw: (CGContext, CGRect) -> Void) -> [RGBColor] {
        let width = ScreenProtocol.width
        let height = ScreenProtocol.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(bounds)
            draw(context, bounds)
        }
        return stride(from: 0, to: bytes.count, by: 4).map { RGBColor(red: bytes[$0], green: bytes[$0 + 1], blue: bytes[$0 + 2]) }
    }
}

private extension Array where Element == RGBColor {
    func withDelay(_ delay: Int) -> ScreenFrame {
        ScreenFrame(pixels: self, delay: delay)
    }
}

extension ScreenImage {
    /// Saves the frame as the keyboard will show it, after RGB565 rounding.
    static func writePreview(_ frame: ScreenFrame, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ScreenImageError.unreadable
        }
        CGImageDestinationAddImage(destination, preview(of: frame), nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenImageError.unreadable }
    }

    static func preview(of frame: ScreenFrame) -> CGImage {
        let bytes = frame.pixels.flatMap { color -> [UInt8] in
            let value = ScreenProtocol.rgb565(color)
            let red = UInt8(value >> 11), green = UInt8((value >> 5) & 0x3f), blue = UInt8(value & 0x1f)
            return [red << 3 | red >> 2, green << 2 | green >> 4, blue << 3 | blue >> 2, 0xff]
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: ScreenProtocol.width, height: ScreenProtocol.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: ScreenProtocol.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return image
    }
}
