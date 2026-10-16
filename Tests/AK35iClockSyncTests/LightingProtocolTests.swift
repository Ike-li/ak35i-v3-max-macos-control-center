import XCTest
@testable import AK35iClockSync

final class LightingProtocolTests: XCTestCase {
    /// Byte-for-byte the sequence that turned the keyboard static green on
    /// 2026-10-16 and survived a replug (docs/STATIC_REVERSING.md).
    func testBuildsDeviceVerifiedStaticGreenSequence() throws {
        let effect = try LightingEffect(
            mode: .staticColor,
            brightness: 5,
            color: .solid(RGBColor(red: 0x00, green: 0xff, blue: 0x00))
        )

        let packets = LightingProtocol.packets(for: effect)

        XCTAssertEqual(packets.map(\.expectsAck), [true, true, false, true, false])
        XCTAssertTrue(packets.allSatisfy { $0.report.count == 65 && $0.report[0] == 0 })
        XCTAssertEqual(Array(packets[0].report[1...9]), [0x04, 0x18, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(packets[1].report[1...9]), [0x04, 0x13, 0, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(
            Array(packets[2].report[1...16]),
            [0x01, 0x00, 0xff, 0x00, 0, 0, 0, 0, 0x00, 0x05, 0x03, 0x00, 0, 0, 0xaa, 0x55]
        )
        XCTAssertTrue(packets[2].report[17...].allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(packets[3].report[1...2]), [0x04, 0x02])
        XCTAssertEqual(Array(packets[4].report[1...2]), [0x04, 0xf0])
    }

    func testOffModeSendsOnlyModeAndTrailer() throws {
        let data = LightingProtocol.packets(for: try LightingEffect(mode: .off))[2].report

        XCTAssertEqual(data[1], 0)
        XCTAssertTrue(data[2...14].allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(data[15...16]), [0xaa, 0x55])
    }

    func testModesWithoutColorControlsSendDriverDefaultColor() throws {
        let data = LightingProtocol.packets(for: try LightingEffect(mode: .spectrumCycle, speed: 1))[2].report

        XCTAssertEqual(Array(data[1...12]), [0x08, 0xff, 0x00, 0x00, 0, 0, 0, 0, 0x01, 0x05, 0x01, 0x00])
    }

    func testRejectsBrightnessAndSpeedOutsideDriverSliderRange() {
        XCTAssertThrowsError(try LightingEffect(mode: .wave, brightness: 6)) { error in
            XCTAssertEqual(error as? LightingEffectError, .outOfRange(.brightness, value: 6, allowed: Array(0...5)))
        }
        XCTAssertThrowsError(try LightingEffect(mode: .wave, speed: -1)) { error in
            XCTAssertEqual(error as? LightingEffectError, .outOfRange(.speed, value: -1, allowed: Array(0...5)))
        }
        XCTAssertNoThrow(try LightingEffect(mode: .wave, brightness: 0, speed: 5))
    }

    func testOnlyAllowsDirectionsTheDriverCanSendForEachMode() {
        XCTAssertNoThrow(try LightingEffect(mode: .wave, direction: 1))
        XCTAssertThrowsError(try LightingEffect(mode: .wave, direction: 2)) { error in
            XCTAssertEqual(error as? LightingEffectError, .outOfRange(.direction, value: 2, allowed: [0, 1]))
        }
        XCTAssertNoThrow(try LightingEffect(mode: .crossColor, direction: 3))
        XCTAssertThrowsError(try LightingEffect(mode: .crossColor, direction: 1)) { error in
            XCTAssertEqual(error as? LightingEffectError, .outOfRange(.direction, value: 1, allowed: [0, 2, 3]))
        }
        XCTAssertThrowsError(try LightingEffect(mode: .staticColor, direction: 1)) { error in
            XCTAssertEqual(error as? LightingEffectError, .unsupported(.direction, mode: .staticColor))
        }
    }

    func testRejectsParametersTheModeDoesNotExpose() {
        XCTAssertThrowsError(try LightingEffect(mode: .staticColor, speed: 2)) { error in
            XCTAssertEqual(error as? LightingEffectError, .unsupported(.speed, mode: .staticColor))
        }
        XCTAssertThrowsError(try LightingEffect(mode: .spectrumCycle, color: .colorful)) { error in
            XCTAssertEqual(error as? LightingEffectError, .unsupported(.color, mode: .spectrumCycle))
        }
        XCTAssertThrowsError(try LightingEffect(mode: .off, brightness: 3)) { error in
            XCTAssertEqual(error as? LightingEffectError, .unsupported(.brightness, mode: .off))
        }
    }

    func testParsesLightingCommandsAsPreviewUnlessApplied() throws {
        XCTAssertEqual(try AK35iCommandParser.parse(["light", "list"]), .lightingList)
        XCTAssertEqual(
            try AK35iCommandParser.parse(["light", "set", "--mode", "1", "--brightness", "5", "--color", "00ff00"]),
            .lightingSet(try LightingEffect(mode: .staticColor, brightness: 5, color: .solid(RGBColor(red: 0, green: 0xff, blue: 0))), apply: false)
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["light", "set", "--mode", "11", "--speed", "2", "--direction", "1", "--colorful", "--apply"]),
            .lightingSet(try LightingEffect(mode: .wave, speed: 2, direction: 1, color: .colorful), apply: true)
        )
    }

    func testRejectsMalformedLightingOptionsBeforeTouchingTheDevice() {
        for arguments in [
            ["light", "set"],
            ["light", "set", "--mode", "20"],
            ["light", "set", "--mode", "1", "--brightness"],
            ["light", "set", "--mode", "1", "--brightness", "high"],
            ["light", "set", "--mode", "1", "--color", "00ff0"],
            ["light", "set", "--mode", "1", "--color", "00ff00", "--colorful"],
            ["light", "set", "--mode", "1", "--blink"],
        ] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)") { error in
                guard case .invalidUsage = error as? AK35iCommandError else {
                    return XCTFail("\(arguments): \(error)")
                }
            }
        }
        XCTAssertThrowsError(try AK35iCommandParser.parse(["light", "set", "--mode", "8", "--color", "00ff00"])) { error in
            XCTAssertEqual(error as? LightingEffectError, .unsupported(.color, mode: .spectrumCycle))
        }
    }
}
