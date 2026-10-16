import Foundation

/// Host-streamed frame of DeviceDriver.exe 0x428110 (realtime page) and
/// 0x432e70 (music page): `04 20` with 8 chunks, 512 bytes of sequential
/// `[light, R, G, B]` records with no `AA 55`, then `04 02`. The keyboard
/// does not store these frames; the driver resends one every ≥ 30 ms.
enum RealtimeFrameProtocol {
    static let chunkCount = 8

    static func packets(colors: [UInt8: RGBColor]) -> [FeaturePacket] {
        var block = [UInt8](repeating: 0, count: chunkCount * 64)
        for (index, key) in KeyboardLayout.keys.enumerated() {
            let color = colors[key.light] ?? RGBColor(red: 0, green: 0, blue: 0)
            block.replaceSubrange(4 * index..<4 * index + 4, with: [key.light, color.red, color.green, color.blue])
        }
        let chunks = (0..<chunkCount).map { index in
            FeaturePacket(report: [0] + block[index * 64..<(index + 1) * 64], expectsAck: false)
        }
        return [FeaturePacket(report: LightingProtocol.command(0x20, followingPackets: UInt8(chunkCount)), expectsAck: true)]
            + chunks
            + [FeaturePacket(report: LightingProtocol.command(0x02), expectsAck: true)]
    }
}

enum FeatureStreamWriter {
    /// Mirrors DeviceDriver.exe 0x44fc90: commands wait 5 ms before and after
    /// the write and are re-sent once when the keyboard answers busy (`0xFF`);
    /// chunks are 2 ms apart. Returns false, sending nothing more, when the
    /// first command is not acknowledged, as 0x428110 skips that frame.
    static func sendFrame(
        _ packets: [FeaturePacket],
        to device: FeatureReportDevice,
        sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) throws -> Bool {
        var acknowledged = true
        for (index, packet) in packets.enumerated() {
            guard packet.expectsAck else {
                try device.writeFeature(packet.report, packetIndex: index + 1)
                sleep(0.002)
                continue
            }
            sleep(0.005)
            try device.writeFeature(packet.report, packetIndex: index + 1)
            sleep(0.005)
            var response = (try? device.readFeature()) ?? []
            if response.count >= 4, response[3] == 0xff {
                try device.writeFeature(packet.report, packetIndex: index + 1)
                sleep(0.005)
                response = (try? device.readFeature()) ?? []
            }
            let ok = FeatureAck.isAcknowledged(report: packet.report, response: response)
            if index == 0, !ok { return false }
            acknowledged = acknowledged && ok
        }
        return acknowledged
    }
}

/// Effects drawn on the Mac and streamed frame by frame. They are this
/// project's own designs; the driver's animations live in mui.dll.
enum LiveEffect: Equatable {
    case solid(RGBColor)
    case breathing(RGBColor)
    case wave
    case starry(RGBColor)
    /// Spectrum bars driven by the Mac's system audio output.
    case music
}

struct LiveRequest: Equatable {
    var effect: LiveEffect
    /// 1 (slowest) to 5 (fastest).
    var speed = 3
    /// Stop after this many seconds; nil streams until interrupted.
    var seconds: Int?
}

struct LiveAnimation {
    static let speeds = Array(1...5)

    let request: LiveRequest
    private var generator: AnyGenerator
    /// Start time of every twinkling key in the starry effect.
    private var stars: [UInt8: TimeInterval] = [:]
    private var lastTime: TimeInterval?
    private let audio: AudioSampleSource?
    private let analyzer = SpectrumAnalyzer()
    private var meter = MusicMeter()

    init(
        request: LiveRequest,
        generator: some RandomNumberGenerator = SystemRandomNumberGenerator(),
        audio: AudioSampleSource? = nil
    ) {
        self.request = request
        self.generator = AnyGenerator(base: generator)
        self.audio = audio
    }

    /// Seconds per breath, per pass of the rainbow, or per twinkle.
    static func period(speed: Int) -> TimeInterval {
        [1: 6.0, 2: 4.5, 3: 3.0, 4: 2.0, 5: 1.2][speed] ?? 3.0
    }

    mutating func frame(at time: TimeInterval) -> [UInt8: RGBColor] {
        let period = Self.period(speed: request.speed)
        defer { lastTime = time }
        switch request.effect {
        case .solid(let color):
            return Self.fill { _ in color }
        case .breathing(let color):
            let level = 0.5 - 0.5 * cos(2 * Double.pi * time / period)
            return Self.fill { _ in color.scaled(level) }
        case .wave:
            let phase = (time / period).truncatingRemainder(dividingBy: 1)
            return Self.fill { key in
                let position = (Double(key.x) + Double(key.width) / 2 - 30) / 740
                var hue = (position - phase).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
                return RGBColor(hue: hue)
            }
        case .starry(let color):
            let elapsed = lastTime.map { max(time - $0, 0) } ?? 0
            let spawnRate = 24 / period
            var spawns = Int(spawnRate * elapsed)
            if Double.random(in: 0..<1, using: &generator) < spawnRate * elapsed - Double(spawns) { spawns += 1 }
            for _ in 0..<spawns {
                let key = KeyboardLayout.keys.randomElement(using: &generator)!
                if stars[key.light] == nil { stars[key.light] = time }
            }
            let life = period / 2
            stars = stars.filter { time - $0.value < life }
            return Self.fill { key in
                guard let start = stars[key.light] else { return RGBColor(red: 0, green: 0, blue: 0) }
                return color.scaled(sin(Double.pi * (time - start) / life))
            }
        case .music:
            return MusicVisualizer.frame(bands: musicBands())
        }
    }

    /// Band levels of the latest audio, falling smoothly.
    mutating func musicBands() -> [Double] {
        let (samples, sampleRate) = audio?.latestSamples() ?? ([], 48_000)
        return meter.update(analyzer.bands(samples: samples, sampleRate: sampleRate))
    }

    private static func fill(_ color: (KeyboardKey) -> RGBColor) -> [UInt8: RGBColor] {
        Dictionary(uniqueKeysWithValues: KeyboardLayout.keys.map { ($0.light, color($0)) })
    }
}

private struct AnyGenerator: RandomNumberGenerator {
    var base: any RandomNumberGenerator
    mutating func next() -> UInt64 { base.next() }
}

extension RGBColor {
    func scaled(_ level: Double) -> RGBColor {
        let level = min(max(level, 0), 1)
        func channel(_ value: UInt8) -> UInt8 { UInt8((Double(value) * level).rounded()) }
        return RGBColor(red: channel(red), green: channel(green), blue: channel(blue))
    }

    /// Fully saturated, full-brightness colour for a hue in 0..<1.
    init(hue: Double) {
        let scaled = hue * 6
        let sector = Int(scaled) % 6
        let rising = UInt8(((scaled - Double(Int(scaled))) * 255).rounded())
        let falling = 255 - rising
        switch sector {
        case 0: self.init(red: 255, green: rising, blue: 0)
        case 1: self.init(red: falling, green: 255, blue: 0)
        case 2: self.init(red: 0, green: 255, blue: rising)
        case 3: self.init(red: 0, green: falling, blue: 255)
        case 4: self.init(red: rising, green: 0, blue: 255)
        default: self.init(red: 255, green: 0, blue: falling)
        }
    }
}

/// Set from the SIGINT handler and read by the streaming loop.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
