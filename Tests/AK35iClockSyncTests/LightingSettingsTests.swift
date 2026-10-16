import CoreGraphics
import XCTest
@testable import AK35iClockSync

/// CoreGraphics also brings in QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

final class LightingSettingsTests: XCTestCase {
    private let green = RGBColor(red: 0x00, green: 0xff, blue: 0x00)

    func testFormStateForStaticGreenMatchesTheDeviceVerifiedEffect() throws {
        let settings = LightingSettings(mode: .staticColor, brightness: 5, colorful: false, color: green)

        XCTAssertEqual(
            try settings.effect(),
            try LightingEffect(mode: .staticColor, brightness: 5, color: .solid(green))
        )
    }

    func testSwitchingModesDropsControlsTheNewModeDoesNotShow() throws {
        let leftover = LightingSettings(mode: .spectrumCycle, brightness: 4, speed: 1, direction: 3, colorful: false, color: green)

        XCTAssertEqual(try leftover.effect(), try LightingEffect(mode: .spectrumCycle, brightness: 4, speed: 1))
        XCTAssertEqual(try LightingSettings(mode: .off, brightness: 2).effect(), try LightingEffect(mode: .off))
    }

    func testDirectionFallsBackToDriverDefaultWhenNotOfferedByTheMode() throws {
        let fromCrossColor = LightingSettings(mode: .wave, direction: 3)

        XCTAssertEqual(try fromCrossColor.effect().direction, 0)
        XCTAssertEqual(try LightingSettings(mode: .wave, direction: 1).effect().direction, 1)
    }

    func testConvertsPickedColorToSRGBBytes() throws {
        let picked = try XCTUnwrap(CGColor(srgbRed: 0, green: 1, blue: 0.5, alpha: 1))

        XCTAssertEqual(RGBColor(cgColor: picked), RGBColor(red: 0x00, green: 0xff, blue: 0x80))
    }
}
