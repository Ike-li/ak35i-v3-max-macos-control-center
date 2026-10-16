import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

final class MusicTests: XCTestCase {
    /// The realtime music effect runs the driver's engine on the latest
    /// system audio, one engine frame per 15 ms.
    func testMusicEffectDrawsTheLatestAudio() {
        var state: UInt32 = 1
        let loud = (0..<2048).map { _ -> Float in
            state = state &* 1_664_525 &+ 1_013_904_223
            return 0.1 * (Float(state >> 8) / Float(1 << 24) * 2 - 1)
        }
        let source = FakeAudioSource(samples: loud)
        var animation = LiveAnimation(request: LiveRequest(effect: .music, music: DriverMusicSettings(foreground: .white)), audio: source)

        XCTAssertTrue(animation.frame(at: 0).values.allSatisfy { $0 == RGBColor(red: 254, green: 254, blue: 254) })
        XCTAssertEqual(animation.musicHeights(at: 0).prefix(18).max(), 6)

        source.samples = Array(repeating: 0, count: 2048)
        XCTAssertFalse(DriverMusicEngine.hasLight(animation.frame(at: 1)))
        XCTAssertEqual(animation.musicHeights(at: 1), Array(repeating: 0, count: DriverMusicEngine.columns))
    }
}

private final class FakeAudioSource: AudioSampleSource, @unchecked Sendable {
    var samples: [Float]

    init(samples: [Float]) {
        self.samples = samples
    }

    func latestSamples() -> (samples: [Float], sampleRate: Double) { (samples, 48_000) }
}
