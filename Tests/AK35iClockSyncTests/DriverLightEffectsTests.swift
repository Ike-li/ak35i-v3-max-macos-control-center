import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

/// Expectations follow the reverse-engineered mui.dll CustomLightMode
/// (docs/STATIC_REVERSING.md, 「驱动原版实时灯效」).
final class DriverLightEffectsTests: XCTestCase {
    private typealias T = DriverLightTables
    private let red = RGBColor(red: 0xff, green: 0, blue: 0)

    private func light(_ usage: UInt8) -> UInt8 {
        KeyboardLayout.keys.first { $0.usage == usage }!.light
    }

    private func light(row: Int, column: Int) -> UInt8 {
        let index = T.rowColumn.firstIndex { $0.row == row && $0.column == column }!
        return KeyboardLayout.keys[index].light
    }

    /// hue(h) = (H[h+64], H[h+128], H[h]) scaled by (c × brightness) >> 8.
    private func hue(_ h: Int, brightness: UInt8) -> RGBColor {
        func scale(_ value: UInt8) -> UInt8 { UInt8((Int(value) * Int(brightness)) >> 8) }
        return RGBColor(red: scale(T.hue[(h + 64) % 192]), green: scale(T.hue[(h + 128) % 192]), blue: scale(T.hue[h % 192]))
    }

    private func engine(_ effect: DriverLightEffect, colorful: Bool = true, steps: Int) -> DriverLightEngine {
        var engine = DriverLightEngine(effect: effect, color: red, colorful: colorful)
        for _ in 0..<steps { engine.step() }
        return engine
    }

    /// SetSpeed 0x10020ff0: 15 − speed ticks of 16 ms, at least one.
    func testSpeedSetsTheStepInterval() {
        XCTAssertEqual(DriverLightEngine.stepInterval(speed: 15), 0.016, accuracy: 1e-9)
        XCTAssertEqual(DriverLightEngine.stepInterval(speed: 14), 0.016, accuracy: 1e-9)
        XCTAssertEqual(DriverLightEngine.stepInterval(speed: 13), 0.032, accuracy: 1e-9)
        XCTAssertEqual(DriverLightEngine.stepInterval(speed: 1), 0.224, accuracy: 1e-9)
    }

    /// Static On is never updated; brightness 255 gives (255 × 255) >> 8.
    func testStaticOnHoldsTheColour() {
        let colors = engine(.staticOn, colorful: false, steps: 40).frame
        XCTAssertEqual(colors.count, KeyboardLayout.keys.count)
        XCTAssertTrue(colors.values.allSatisfy { $0 == RGBColor(red: 254, green: 0, blue: 0) })
    }

    /// Starlight counts each key down from its phase and relights it at 255.
    func testStarlightCountsDownAndRelights() {
        let esc = light(0x29)
        XCTAssertEqual(T.starPhases[0], 120)
        XCTAssertEqual(engine(.starlight, colorful: false, steps: 1).frame[esc], RGBColor(red: UInt8((0xff * 120) >> 8), green: 0, blue: 0))
        XCTAssertEqual(engine(.starlight, colorful: false, steps: 121).frame[esc], RGBColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(engine(.starlight, colorful: false, steps: 122).frame[esc], RGBColor(red: 254, green: 0, blue: 0))
        let recoloured = engine(.starlight, steps: 122).frame[esc]!
        XCTAssertNotEqual(recoloured, RGBColor(red: 254, green: 0, blue: 0), "colourful stars take a new colour on relighting")
    }

    /// Breathing colours each column from its table (stored G, R, B) and gives
    /// every key the same brightness from B128.
    func testBreathingSharesOneBrightness() {
        let esc = light(0x29)  // row 0, column 1
        let colors = engine(.breathing, steps: 64).frame
        let level = Int(T.breath[63])
        let expected = RGBColor(
            red: UInt8((Int(T.breathColumnColors[4]) * level) >> 8),
            green: UInt8((Int(T.breathColumnColors[3]) * level) >> 8),
            blue: UInt8((Int(T.breathColumnColors[5]) * level) >> 8)
        )
        XCTAssertEqual(colors[esc], expected)
        XCTAssertTrue(engine(.breathing, steps: 1).frame.values.allSatisfy { $0 == RGBColor(red: 0, green: 0, blue: 0) }, "B128 starts at 0")
    }

    /// Colourful Fountain moves each ring's hue and wave phase one step.
    func testFountainLightsRings() {
        let usage = T.fountainRings[0]
        let colors = engine(.fountain, steps: 1).frame
        XCTAssertEqual(colors[light(usage)], hue(Int(T.fountainHues[0]) + 1, brightness: T.wave[(Int(T.fountainPhases[0]) + 1) % 96]))
    }

    /// Rainbow Wave runs hue and phase backwards per row; hues start at 32 × row.
    func testRainbowWaveMovesRows() {
        let colors = engine(.rainbowWave, steps: 1).frame
        for row in 0..<6 {
            let key = T.rowColumn.firstIndex { $0.row == row }!
            XCTAssertEqual(
                colors[KeyboardLayout.keys[key].light],
                hue((32 * row + 191) % 192, brightness: T.wave[(Int(T.waveRowPhases[row]) + 95) % 96]),
                "row \(row)"
            )
        }
    }

    /// Following Currents runs hue and phase backwards per column.
    func testFollowingCurrentsMovesColumns() {
        let colors = engine(.currents, steps: 2).frame
        let column = 3
        XCTAssertEqual(
            colors[light(row: 1, column: column)],
            hue((Int(T.currentHues[column]) + 190) % 192, brightness: T.wave[(Int(T.currentPhases[column]) + 94) % 96])
        )
    }

    /// Rotating moves 45 groups of three keys forwards.
    func testRotatingMovesGroups() {
        let colors = engine(.rotating, steps: 3).frame
        let group = (0..<45).first { T.rotateGroups[3 * $0] != 0 }!
        XCTAssertEqual(
            colors[light(T.rotateGroups[3 * group])],
            hue(Int(T.rotateHues[group]) + 3, brightness: T.wave[(Int(T.rotatePhases[group]) + 3) % 96])
        )
    }

    /// Fluttering recolours keys from its table and never dims them. The
    /// colour index reaches 106, one past the 106 colours, where the driver
    /// reads two padding bytes and the first byte of the next table: (0, 0, 0).
    func testFlutteringRecoloursWithoutDimming() {
        let start = engine(.fluttering, steps: 0).frame
        let later = engine(.fluttering, steps: 12).frame
        let changed = later.filter { $0.value != start[$0.key] }
        XCTAssertFalse(changed.isEmpty)
        func full(_ offset: Int) -> UInt8 { UInt8((Int(T.rainColors[offset]) * 255) >> 8) }
        let palette = stride(from: 0, to: 321, by: 3).map { (offset: Int) -> RGBColor in
            RGBColor(red: full(offset), green: full(offset + 1), blue: full(offset + 2))
        }
        XCTAssertTrue(changed.values.allSatisfy { palette.contains($0) })
    }

    /// Without “colourful” the chosen colour stays and only brightness moves.
    func testSingleColourOnlyChangesBrightness() {
        let colors = engine(.fountain, colorful: false, steps: 5).frame
        XCTAssertTrue(colors.values.allSatisfy { $0.green == 0 && $0.blue == 0 })
        XCTAssertGreaterThan(Set(colors.values.map(\.red)).count, 1)
    }
}
