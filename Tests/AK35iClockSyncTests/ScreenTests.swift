import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

final class ScreenTests: XCTestCase {
    private let red = RGBColor(red: 0xff, green: 0, blue: 0)
    private let blue = RGBColor(red: 0, green: 0, blue: 0xff)

    private func frame(_ color: RGBColor, delay: Int = 100) -> ScreenFrame {
        ScreenFrame(pixels: Array(repeating: color, count: ScreenProtocol.width * ScreenProtocol.height), delay: delay)
    }

    func testPacksPixelsAsLittleEndianRGB565LikeMuiDll() {
        XCTAssertEqual(ScreenProtocol.rgb565(red), 0xf800)
        XCTAssertEqual(ScreenProtocol.rgb565(RGBColor(red: 0, green: 0xff, blue: 0)), 0x07e0)
        XCTAssertEqual(ScreenProtocol.rgb565(blue), 0x001f)
        XCTAssertEqual(ScreenProtocol.rgb565(RGBColor(red: 0x87, green: 0x46, blue: 0x2c)), 0x8225)
    }

    /// Image layout of DeviceDriver.exe 0x422b00 with gif_headlength 256 and 240 × 135.
    func testOneFrameUploadMatchesTheDriverImage() throws {
        var pixels = frame(blue).pixels
        pixels[0] = red
        pixels[ScreenProtocol.width] = RGBColor(red: 0xff, green: 0xff, blue: 0xff)
        let upload = try ScreenProtocol.upload(frames: [ScreenFrame(pixels: pixels, delay: 100)])
        let image = upload.blocks.flatMap { $0 }

        XCTAssertEqual(upload.blocks.count, 16)
        XCTAssertTrue(upload.blocks.allSatisfy { $0.count == 4096 })
        XCTAssertEqual(upload.start.map(\.expectsAck), [true, true])
        XCTAssertEqual(Array(upload.start[0].report[1...2]), [0x04, 0x18])
        XCTAssertEqual(Array(upload.start[1].report[1...10]), [0x04, 0x72, 0x01, 0, 0, 0, 0, 0, 0x10, 0x00])
        XCTAssertEqual(Array(upload.commit.report[1...2]), [0x04, 0x02])
        XCTAssertTrue(upload.commit.expectsAck)

        XCTAssertEqual(Array(image[0...2]), [0x01, 50, 0xff])
        XCTAssertTrue(image[2..<256].allSatisfy { $0 == 0xff })
        XCTAssertEqual(Array(image[256...259]), [0x00, 0xf8, 0x1f, 0x00], "first pixel red, then blue")
        XCTAssertEqual(Array(image[(256 + 480)...(257 + 480)]), [0xff, 0xff], "second row starts after 240 pixels")
        XCTAssertEqual(Array(image[(256 + 64_798)...(256 + 64_799)]), [0x1f, 0x00])
        XCTAssertTrue(image[(256 + 64_800)...].allSatisfy { $0 == 0xff })
    }

    func testFrameDelaysUseTwoMillisecondUnitsWithoutWrapping() throws {
        let delays = [100, 1, 2, 3, 510, 600]
        let upload = try ScreenProtocol.upload(frames: delays.map { frame(red, delay: $0) })
        let header = upload.blocks[0]

        XCTAssertEqual(header[0], 6)
        XCTAssertEqual(Array(header[1...6]), [50, 1, 1, 1, 255, 255])
        XCTAssertEqual(header[7], 0xff)
    }

    func testAllowsTheDriversFrameLimit() throws {
        let many = try ScreenProtocol.upload(frames: Array(repeating: frame(red), count: 141))
        XCTAssertEqual(many.blocks.count, 2231)
        XCTAssertEqual(Array(many.start[1].report[9...10]), [0xb7, 0x08])

        XCTAssertThrowsError(try ScreenProtocol.upload(frames: Array(repeating: frame(red), count: 142))) { error in
            XCTAssertEqual(error as? ScreenError, .frameCount(142))
        }
        XCTAssertThrowsError(try ScreenProtocol.upload(frames: [])) { error in
            XCTAssertEqual(error as? ScreenError, .frameCount(0))
        }
    }

    /// An image split into coloured rectangles given in top-left coordinates.
    private func image(width: Int, height: Int, fills: [(CGRect, RGBColor)]) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for (rect, color) in fills {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }
        return context.makeImage()!
    }

    private func pixel(_ frame: ScreenFrame, _ x: Int, _ y: Int) -> RGBColor {
        frame.pixels[y * ScreenProtocol.width + x]
    }

    func testKeepsRowsTopToBottomAndColumnsLeftToRight() {
        let picture = image(width: 240, height: 135, fills: [
            (CGRect(x: 0, y: 0, width: 240, height: 60), red),
            (CGRect(x: 0, y: 60, width: 240, height: 75), blue),
            (CGRect(x: 0, y: 0, width: 10, height: 10), RGBColor(red: 0xff, green: 0xff, blue: 0xff)),
        ])
        let frame = ScreenImage.frame(from: picture, delay: 100)

        XCTAssertEqual(frame.pixels.count, 240 * 135)
        XCTAssertEqual(pixel(frame, 2, 2), RGBColor(red: 0xff, green: 0xff, blue: 0xff))
        XCTAssertEqual(pixel(frame, 120, 30), red)
        XCTAssertEqual(pixel(frame, 120, 120), blue)
    }

    func testScalesToFitWithoutDistortion() {
        let wide = ScreenImage.frame(from: image(width: 480, height: 270, fills: [
            (CGRect(x: 0, y: 0, width: 240, height: 270), red),
            (CGRect(x: 240, y: 0, width: 240, height: 270), blue),
        ]), delay: 100)
        XCTAssertEqual(pixel(wide, 5, 67), red)
        XCTAssertEqual(pixel(wide, 234, 67), blue)

        let green = RGBColor(red: 0, green: 0xff, blue: 0)
        let square = ScreenImage.frame(from: image(width: 100, height: 100, fills: [(CGRect(x: 0, y: 0, width: 100, height: 100), green)]), delay: 100)
        XCTAssertEqual(pixel(square, 10, 67), RGBColor(red: 0, green: 0, blue: 0), "letterboxed")
        XCTAssertEqual(pixel(square, 120, 67), green)
        XCTAssertEqual(pixel(square, 230, 67), RGBColor(red: 0, green: 0, blue: 0))
    }

    func testReadsEveryGifFrameWithItsDelay() throws {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)!
        for (color, delay) in [(red, 0.05), (blue, 0.2)] {
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, image(width: 240, height: 135, fills: [(CGRect(x: 0, y: 0, width: 240, height: 135), color)]), properties)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let frames = try ScreenImage.frames(from: data as Data)
        XCTAssertEqual(frames.map(\.delay), [50, 200])
        XCTAssertEqual(pixel(frames[0], 120, 67).red, 0xff)
        XCTAssertEqual(pixel(frames[1], 120, 67).blue, 0xff)
        XCTAssertThrowsError(try ScreenImage.frames(from: Data("not an image".utf8)))
    }

    func testTestPatternShowsOrientation() {
        let frame = ScreenImage.testPattern()
        XCTAssertEqual(pixel(frame, 3, 3), RGBColor(red: 0xff, green: 0xff, blue: 0xff))
        XCTAssertEqual(pixel(frame, 236, 131), RGBColor(red: 0, green: 0, blue: 0))
        XCTAssertGreaterThan(pixel(frame, 30, 120).red, 0xc0, "rainbow starts red on the left")
    }

    func testParsesScreenCommands() throws {
        XCTAssertEqual(try AK35iCommandParser.parse(["screen", "set", "--test-pattern"]), .screenSet(.testPattern, preview: nil, apply: false))
        XCTAssertEqual(
            try AK35iCommandParser.parse(["screen", "set", "cat.gif", "--preview", "out.png", "--apply"]),
            .screenSet(.file("cat.gif"), preview: "out.png", apply: true)
        )
        for arguments in [["screen", "set"], ["screen", "set", "a.png", "--test-pattern"], ["screen", "set", "a.png", "b.png"], ["screen", "set", "a.png", "--preview"]] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)")
        }
    }
}
