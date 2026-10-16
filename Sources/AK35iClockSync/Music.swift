import Foundation

/// Latest mono audio, filled from the capture thread and read per frame.
protocol AudioSampleSource: AnyObject, Sendable {
    func latestSamples() -> (samples: [Float], sampleRate: Double)
}

/// 2.4G music frame of DeviceDriver.exe 0x4330b0. The keyboard has no
/// per-key realtime frame over 2.4G; firmware 0x6A18 instead lights 18
/// columns from the bottom row up, P[6..23] rows each (0–6), in palette
/// colours: P[3] for lit cells and P[4] for the rest, the music page's mode
/// numbers. Palette 0 is off and 1 a gradient by row (0x0F826). P[5], the
/// driver's background brightness, is stored but never read.
enum MusicBarsProtocol {
    static let columns = 18
    static let rows = 6

    static func packet(heights: [Int], foreground: UInt8 = 1, background: UInt8 = 0, brightness: UInt8 = 0) -> [UInt8] {
        let bars = heights.prefix(columns).map { UInt8(min(max($0, 0), rows)) }
        return WirelessProtocol.packet(0x0b, length: 0x1c, data: [foreground, background, brightness] + bars)
    }
}
