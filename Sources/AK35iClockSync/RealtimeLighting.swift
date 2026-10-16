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

/// Effects drawn on the Mac and streamed frame by frame.
enum LiveEffect: Equatable {
    /// One of the driver's realtime effects, ported from mui.dll.
    case driver(DriverLightEffect)
    /// Spectrum bars driven by the Mac's system audio output.
    case music
}

struct LiveRequest: Equatable {
    var effect: LiveEffect
    /// The driver's defaults: red, “colourful” ticked, speed 15.
    var color = RGBColor(red: 0xff, green: 0, blue: 0)
    var colorful = true
    /// 1 (slowest) to 15 (fastest).
    var speed = 15
    /// Stop after this many seconds; nil streams until interrupted.
    var seconds: Int?
}

struct LiveAnimation {
    static let speeds = Array(1...15)

    let request: LiveRequest
    private var engine: DriverLightEngine?
    private var steps = 0
    private let audio: AudioSampleSource?
    private let analyzer = SpectrumAnalyzer()
    private var meter = MusicMeter()

    init(request: LiveRequest, audio: AudioSampleSource? = nil) {
        self.request = request
        self.audio = audio
        if case .driver(let effect) = request.effect {
            engine = DriverLightEngine(effect: effect, color: request.color, colorful: request.colorful)
        }
    }

    mutating func frame(at time: TimeInterval) -> [UInt8: RGBColor] {
        guard var engine else { return MusicVisualizer.frame(bands: musicBands()) }
        let due = Int(time / DriverLightEngine.stepInterval(speed: request.speed))
        while steps < due {
            engine.step()
            steps += 1
        }
        self.engine = engine
        return engine.frame
    }

    /// Band levels of the latest audio, falling smoothly.
    mutating func musicBands() -> [Double] {
        let (samples, sampleRate) = audio?.latestSamples() ?? ([], 48_000)
        return meter.update(analyzer.bands(samples: samples, sampleRate: sampleRate))
    }
}

extension RGBColor {
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
