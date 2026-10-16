import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

/// Expectations follow the reverse-engineered music page of DeviceDriver.exe
/// (docs/STATIC_REVERSING.md, 「驱动原版音乐律动」).
final class DriverMusicTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let silence = [Float](repeating: 0, count: 2048)

    private func tone(_ frequency: Double, amplitude: Float) -> [Float] {
        (0..<2048).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// Deterministic broadband noise.
    private func noise(amplitude: Float) -> [Float] {
        var state: UInt32 = 1
        return (0..<2048).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return amplitude * (Float(state >> 8) / Float(1 << 24) * 2 - 1)
        }
    }

    private func light(row: Int, column: Int) -> UInt8 {
        let index = DriverLightTables.rowColumn.firstIndex { $0.row == row && $0.column == column }!
        return KeyboardLayout.keys[index].light
    }

    private func lights(inRow row: Int) -> [UInt8] {
        DriverLightTables.rowColumn.enumerated().filter { $0.element.row == row }.map { KeyboardLayout.keys[$0.offset].light }
    }

    private func engine(_ settings: DriverMusicSettings, samples: [Float], until time: TimeInterval = 0) -> DriverMusicEngine {
        var engine = DriverMusicEngine(settings: settings)
        engine.advance(to: time, samples: samples)
        return engine
    }

    /// Integer HSV of DeviceDriver.exe 0x45ba00.
    func testHSVMatchesTheDriver() {
        XCTAssertEqual(DriverMusicEngine.hsv(hue: 0, saturation: 255, value: 255), RGBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(DriverMusicEngine.hsv(hue: 90, saturation: 255, value: 255), RGBColor(red: 127, green: 255, blue: 0))
        XCTAssertEqual(DriverMusicEngine.hsv(hue: 120, saturation: 255, value: 255), RGBColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(DriverMusicEngine.hsv(hue: 240, saturation: 255, value: 255), RGBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(DriverMusicEngine.hsv(hue: 450, saturation: 255, value: 255), RGBColor(red: 127, green: 255, blue: 0), "hue wraps at 360")
        XCTAssertEqual(DriverMusicEngine.hsv(hue: 200, saturation: 0, value: 77), RGBColor(red: 77, green: 77, blue: 77))
    }

    /// The driver multiplies samples by 2 × amplitude × 5 and does not
    /// normalise the FFT, so ordinary loud sound fills every level: all keys
    /// take the foreground. Green/Yellow/Red runs red at the top to green at
    /// the bottom, (c × 255) >> 8.
    func testLoudSoundLightsEveryKeyInTheForeground() {
        let colors = engine(DriverMusicSettings(foreground: .greenYellowRed), samples: noise(amplitude: 0.1)).frame
        let red = RGBColor(red: 254, green: 0, blue: 0)
        let yellow = RGBColor(red: 254, green: 254, blue: 0)
        let green = RGBColor(red: 0, green: 254, blue: 0)
        for (row, expected) in [red, red, yellow, yellow, green, green].enumerated() {
            XCTAssertTrue(lights(inRow: row).allSatisfy { colors[$0] == expected }, "row \(row)")
        }
    }

    /// Silence shows the background: White at brightness 50 is
    /// (255 × int(50 × 2.55)) >> 8 = 126.
    func testSilenceShowsTheBackground() {
        let music = engine(DriverMusicSettings(background: .white, backgroundBrightness: 50), samples: silence)
        XCTAssertEqual(music.frame.count, KeyboardLayout.keys.count)
        XCTAssertTrue(music.frame.values.allSatisfy { $0 == RGBColor(red: 126, green: 126, blue: 126) })
        XCTAssertTrue(DriverMusicEngine.hasLight(music.frame))
        XCTAssertEqual(music.heights, Array(repeating: 0, count: 22))
    }

    /// With no background, silence is black and the driver sends no frame.
    func testSilenceWithoutBackgroundSendsNothing() {
        XCTAssertFalse(DriverMusicEngine.hasLight(engine(DriverMusicSettings(), samples: silence).frame))
        XCTAssertTrue(DriverMusicEngine.hasLight(engine(DriverMusicSettings(), samples: noise(amplitude: 0.1)).frame))
        XCTAssertFalse(DriverMusicEngine.hasLight([1: RGBColor(red: 1, green: 0, blue: 0)]), "only colours above 1 count")
    }

    /// FFT bin j (j × 93.75 Hz at 48 kHz) feeds levels 4j…4j+3, and column c
    /// reads level 11c: a quiet 2,062.5 Hz tone (bin 22) lights column 8 only.
    func testToneLightsItsOwnColumn() {
        let heights = engine(DriverMusicSettings(), samples: tone(2_062.5, amplitude: 0.001)).heights
        XCTAssertGreaterThan(heights[8], 0)
        XCTAssertEqual(heights[0], 0)
        XCTAssertEqual(heights[20], 0)
    }

    /// Levels fall by 0.8 per 15 ms engine frame once the sound stops:
    /// five frames leave 0.8⁵ ≈ 0.33, above the bottom two thresholds
    /// (7/64, 17/64) only.
    func testBarsFallAfterTheSoundStops() {
        var music = engine(DriverMusicSettings(), samples: noise(amplitude: 0.1))
        XCTAssertEqual(music.heights.prefix(18).max(), 6)
        music.advance(to: 0.08, samples: silence)
        let expected = (0..<22).map { column in
            DriverLightTables.rowColumn.contains { $0.column == column && $0.row == 4 } ? 2
                : DriverLightTables.rowColumn.contains { $0.column == column && $0.row == 5 } ? 1 : 0
        }
        XCTAssertEqual(music.heights, expected, "heights count only cells that have a key")
        music.advance(to: 1, samples: silence)
        XCTAssertEqual(music.heights, Array(repeating: 0, count: 22))
    }

    /// Spectrum Cycle turns 5° per engine frame: frame 24 is HSV(120).
    func testSpectrumCycleTurnsFiveDegreesAFrame() {
        let settings = DriverMusicSettings(background: .spectrumCycle)
        XCTAssertTrue(engine(settings, samples: silence).frame.values.allSatisfy { $0 == RGBColor(red: 255, green: 0, blue: 0) })
        XCTAssertTrue(engine(settings, samples: silence, until: 0.37).frame.values.allSatisfy { $0 == RGBColor(red: 0, green: 255, blue: 0) })
    }

    /// Gradient (色谱) is a colour wheel around canvas (128, 32): the bottom
    /// left key (x 0, y 57) sits at int(atan2(25, −128) × 57.29583 + 180) = 348°.
    func testGradientIsAColourWheel() {
        let colors = engine(DriverMusicSettings(foreground: .gradient), samples: noise(amplitude: 0.1)).frame
        XCTAssertEqual(colors[light(row: 5, column: 0)], RGBColor(red: 255, green: 0, blue: 51))
    }

    func testParsesMusicOptions() throws {
        XCTAssertEqual(try AK35iCommandParser.parse(["live", "music"]), .live(LiveRequest(effect: .music)))
        XCTAssertEqual(DriverMusicSettings(), DriverMusicSettings(foreground: .gradient, background: .off, amplitude: 60, backgroundBrightness: 100))
        XCTAssertEqual(
            try AK35iCommandParser.parse([
                "live", "music", "--foreground", "green-yellow-red", "--background", "white",
                "--amplitude", "30", "--background-brightness", "50", "--seconds", "10",
            ]),
            .live(LiveRequest(
                effect: .music,
                music: DriverMusicSettings(foreground: .greenYellowRed, background: .white, amplitude: 30, backgroundBrightness: 50),
                seconds: 10
            ))
        )
        for arguments in [
            ["live", "music", "--foreground", "off"], ["live", "music", "--foreground", "purple"],
            ["live", "music", "--amplitude", "101"], ["live", "music", "--background-brightness", "-1"],
            ["live", "music", "--color", "ff0000"], ["live", "music", "--speed", "3"],
            ["live", "wave", "--amplitude", "30"],
        ] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)")
        }
    }
}
