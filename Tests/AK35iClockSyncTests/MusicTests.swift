import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

final class MusicTests: XCTestCase {
    private let sampleRate = 48_000.0

    private func sine(_ frequency: Double, amplitude: Float = 1) -> [Float] {
        (0..<SpectrumAnalyzer.windowLength).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    func testSpectrumPutsATonesEnergyInItsBand() {
        let analyzer = SpectrumAnalyzer()
        let low = analyzer.bands(samples: sine(100), sampleRate: sampleRate)
        let high = analyzer.bands(samples: sine(5_000), sampleRate: sampleRate)

        XCTAssertEqual(low.count, SpectrumAnalyzer.bandCount)
        XCTAssertEqual(low.firstIndex(of: low.max()!), SpectrumAnalyzer.band(containing: 100))
        XCTAssertGreaterThan(low.max()!, 0.9)
        XCTAssertLessThan(low[SpectrumAnalyzer.band(containing: 5_000)!], 0.3)
        XCTAssertEqual(high.firstIndex(of: high.max()!), SpectrumAnalyzer.band(containing: 5_000))
        XCTAssertLessThan(high[SpectrumAnalyzer.band(containing: 100)!], 0.3)
    }

    func testSilenceAndQuietSoundsStayDark() {
        let analyzer = SpectrumAnalyzer()
        XCTAssertTrue(analyzer.bands(samples: Array(repeating: 0, count: SpectrumAnalyzer.windowLength), sampleRate: sampleRate).allSatisfy { $0 == 0 })
        let quiet = analyzer.bands(samples: sine(1_000, amplitude: 0.001), sampleRate: sampleRate)
        XCTAssertLessThan(quiet.max()!, 0.1, "-60 dBFS is the floor")
    }

    func testBarsRiseFromTheBottomRowInTheirColumn() {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        XCTAssertTrue(MusicVisualizer.frame(bands: Array(repeating: 0, count: SpectrumAnalyzer.bandCount)).values.allSatisfy { $0 == black })

        var bands = Array(repeating: 0.0, count: SpectrumAnalyzer.bandCount)
        bands[0] = 1
        let full = MusicVisualizer.frame(bands: bands)
        let firstColumn = KeyboardLayout.keys.filter { MusicVisualizer.band(of: $0) == 0 }
        XCTAssertFalse(firstColumn.isEmpty)
        XCTAssertTrue(firstColumn.allSatisfy { full[$0.light] != black })
        XCTAssertTrue(KeyboardLayout.keys.filter { MusicVisualizer.band(of: $0) != 0 }.allSatisfy { full[$0.light] == black })

        bands[0] = 0.5
        let half = MusicVisualizer.frame(bands: bands)
        let lit = Set(firstColumn.filter { half[$0.light] != black }.map(\.y))
        XCTAssertEqual(lit, [230, 196, 164])
        XCTAssertNotEqual(full[KeyboardLayout.light(named: "Esc")!], full[KeyboardLayout.light(named: "LCtrl")!], "top and bottom rows differ in colour")
    }

    func testMeterRisesAtOnceAndFallsGradually() {
        var meter = MusicMeter()
        XCTAssertEqual(meter.update([1, 0]), [1, 0])
        let falling = meter.update([0, 0])
        XCTAssertLessThan(falling[0], 1)
        XCTAssertGreaterThan(falling[0], 0.5)
        XCTAssertEqual(meter.update([0.2, 0.9]).last, 0.9)
    }

    func testMusicEffectDrawsTheLatestAudio() throws {
        let source = FakeAudioSource(samples: sine(100), sampleRate: sampleRate)
        var animation = LiveAnimation(request: LiveRequest(effect: .music), audio: source)
        let black = RGBColor(red: 0, green: 0, blue: 0)

        let loud = animation.frame(at: 0)
        let column = KeyboardLayout.keys.filter { MusicVisualizer.band(of: $0) == SpectrumAnalyzer.band(containing: 100) }
        XCTAssertFalse(column.isEmpty)
        XCTAssertTrue(column.allSatisfy { loud[$0.light] != black })
        XCTAssertEqual(loud[KeyboardLayout.light(named: "NumMinus")!], black)

        source.samples = Array(repeating: 0, count: SpectrumAnalyzer.windowLength)
        for step in 1...40 { _ = animation.frame(at: Double(step) / 30) }
        XCTAssertTrue(animation.frame(at: 2).values.allSatisfy { $0 == black })
        XCTAssertEqual(try AK35iCommandParser.parse(["live", "music", "--seconds", "30"]), .live(LiveRequest(effect: .music, seconds: 30)))
        XCTAssertThrowsError(try AK35iCommandParser.parse(["live", "music", "--color", "ff0000"]))
    }
}

private final class FakeAudioSource: AudioSampleSource, @unchecked Sendable {
    var samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    func latestSamples() -> (samples: [Float], sampleRate: Double) { (samples, sampleRate) }
}
