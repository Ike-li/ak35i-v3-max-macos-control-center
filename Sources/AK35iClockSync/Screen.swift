import Foundation

struct ScreenFrame: Equatable {
    /// 240 × 135 pixels, rows top to bottom, left to right.
    var pixels: [RGBColor]
    /// Milliseconds before the next frame.
    var delay: Int
}

enum ScreenError: LocalizedError, Equatable {
    case frameCount(Int)
    case pixelCount(Int)

    var errorDescription: String? {
        switch self {
        case .frameCount(let count):
            return "屏幕动画须有 1–\(ScreenProtocol.maxFrames) 帧，当前 \(count) 帧。"
        case .pixelCount(let count):
            return "每帧须为 \(ScreenProtocol.width)×\(ScreenProtocol.height) 像素，当前 \(count) 个。"
        }
    }
}

struct ScreenUpload: Equatable {
    /// `04 18` and `04 72` on the Feature interface.
    let start: [FeaturePacket]
    /// 4096-byte Output reports for the screen interface.
    let blocks: [[UInt8]]
    /// `04 02` on the Feature interface.
    let commit: FeaturePacket
}

/// Screen animation upload of DeviceDriver.exe 0x422b00: one `04 72` with the
/// slot and block count, then the image in 4096-byte Output reports. The
/// firmware writes them to its external flash from 0x950000.
enum ScreenProtocol {
    static let width = 240
    static let height = 135
    static let headerLength = 256
    static let blockLength = 4096
    /// `gif_maxframes` in rgb-keyboard.xml.
    static let maxFrames = 141
    /// `gif_count` is 1, so the list selection + 1 is always 1.
    static let slot: UInt8 = 1

    /// mui.dll 0x1003c8f0: R5 G6 B5 from the top bits of each channel.
    static func rgb565(_ color: RGBColor) -> UInt16 {
        UInt16(color.red & 0xf8) << 8 | UInt16(color.green & 0xfc) << 3 | UInt16(color.blue >> 3)
    }

    static func upload(frames: [ScreenFrame]) throws -> ScreenUpload {
        var image = try image(frames: frames)
        let blockCount = (image.count + blockLength - 1) / blockLength
        image += Array(repeating: 0xff, count: blockCount * blockLength - image.count)

        var preamble = LightingProtocol.command(0x72)
        preamble[3] = slot
        preamble[9] = UInt8(blockCount & 0xff)
        preamble[10] = UInt8(blockCount >> 8)
        return ScreenUpload(
            start: [
                FeaturePacket(report: LightingProtocol.command(0x18), expectsAck: true),
                FeaturePacket(report: preamble, expectsAck: true),
            ],
            blocks: (0..<blockCount).map { Array(image[$0 * blockLength..<($0 + 1) * blockLength]) },
            commit: FeaturePacket(report: LightingProtocol.command(0x02), expectsAck: true)
        )
    }

    /// DeviceDriver.exe 0x4233a0, which its 2.4G menu hides: `7F 03 00
    /// <slot> <packet count, 24-bit LE>`, then the image in 28-byte packets
    /// numbered (0x80 + i >> 16, i, i >> 8). Firmware 0x6B80 / 0x6C4A write
    /// them from 0x950000 like the wired upload.
    static func wirelessPackets(frames: [ScreenFrame]) throws -> [[UInt8]] {
        var image = try image(frames: frames)
        let count = (image.count + WirelessProtocol.dataLength - 1) / WirelessProtocol.dataLength
        image += Array(repeating: 0xff, count: count * WirelessProtocol.dataLength - image.count)
        let start = WirelessProtocol.packet(0x7f, length: 0x03, data: [slot, UInt8(count & 0xff), UInt8((count >> 8) & 0xff), UInt8(count >> 16)])
        return [start] + (0..<count).map { index in
            WirelessProtocol.packet(
                0x80 + UInt8(index >> 16),
                length: UInt8(index & 0xff),
                sequence: UInt8((index >> 8) & 0xff),
                data: Array(image[index * WirelessProtocol.dataLength..<(index + 1) * WirelessProtocol.dataLength])
            )
        }
    }

    /// The 256-byte header and the frames, without padding.
    private static func image(frames: [ScreenFrame]) throws -> [UInt8] {
        guard (1...maxFrames).contains(frames.count) else { throw ScreenError.frameCount(frames.count) }
        let frameLength = width * height * 2
        if let bad = frames.first(where: { $0.pixels.count != width * height }) {
            throw ScreenError.pixelCount(bad.pixels.count)
        }

        var image = [UInt8](repeating: 0xff, count: headerLength + frameLength * frames.count)
        image[0] = UInt8(frames.count)
        for (index, frame) in frames.enumerated() {
            // The driver wraps delays over 510 ms; they are capped here instead.
            image[1 + index] = UInt8(min(max(frame.delay / 2, 1), 255))
            var offset = headerLength + index * frameLength
            for pixel in frame.pixels {
                let value = rgb565(pixel)
                image[offset] = UInt8(value & 0xff)
                image[offset + 1] = UInt8(value >> 8)
                offset += 2
            }
        }
        return image
    }
}
