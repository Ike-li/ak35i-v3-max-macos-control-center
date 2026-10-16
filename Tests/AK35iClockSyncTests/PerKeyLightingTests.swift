import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

final class PerKeyLightingTests: XCTestCase {
    func testKeyNamesResolveToTheDriverLightIndices() {
        XCTAssertEqual(KeyboardLayout.keys.count, 104)
        XCTAssertEqual(Set(KeyboardLayout.keys.map { $0.name.lowercased() }).count, 104)
        XCTAssertEqual(Set(KeyboardLayout.keys.map(\.light)).count, 104)
        XCTAssertEqual(KeyboardLayout.light(named: "Esc"), 1)
        XCTAssertEqual(KeyboardLayout.light(named: "esc"), 1)
        XCTAssertEqual(KeyboardLayout.light(named: "1"), 20)
        XCTAssertEqual(KeyboardLayout.light(named: "Num1"), 86)
        XCTAssertEqual(KeyboardLayout.light(named: "Enter"), 85)
        XCTAssertEqual(KeyboardLayout.light(named: "NumEnter"), 106)
        XCTAssertEqual(KeyboardLayout.light(named: "NumPlus"), 123)
        XCTAssertNil(KeyboardLayout.light(named: "F13"))
    }

    private let red = RGBColor(red: 0xff, green: 0, blue: 0)
    private let black = RGBColor(red: 0, green: 0, blue: 0)

    /// Mode switch sent before the Esc-red trial on 2026-10-16.
    func testSwitchesToCustomModeLikeTheDeviceTrial() {
        let packets = LightingProtocol.customModePackets(brightness: 5)

        XCTAssertEqual(packets.map(\.expectsAck), [true, true, false, true, false])
        XCTAssertEqual(Array(packets[1].report[1...9]), [0x04, 0x13, 0, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(
            Array(packets[2].report[1...16]),
            [0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0x05, 0, 0, 0, 0, 0xaa, 0x55]
        )
    }

    func testWritesEveryLayoutKeyInFourByteSlots() {
        let packets = PerKeyProtocol.writePackets(colors: [1: red])
        let block = packets[2...10].flatMap { $0.report.dropFirst() }

        XCTAssertEqual(packets.count, 13)
        XCTAssertTrue(packets.allSatisfy { $0.report.count == 65 && $0.report[0] == 0 })
        XCTAssertEqual(packets.map(\.expectsAck), [true, true] + Array(repeating: false, count: 9) + [true, true])
        XCTAssertEqual(Array(packets[0].report[1...2]), [0x04, 0x18])
        XCTAssertEqual(Array(packets[1].report[1...9]), [0x04, 0x23, 0, 0, 0, 0, 0, 0, 9])
        XCTAssertEqual(Array(packets[11].report[1...2]), [0x04, 0x02])
        XCTAssertEqual(Array(packets[12].report[1...2]), [0x04, 0xf0])

        XCTAssertEqual(block.count, 576)
        XCTAssertEqual(Array(block[0...3]), [0, 0, 0, 0])
        XCTAssertEqual(Array(block[4...7]), [0x01, 0xff, 0x00, 0x00])
        XCTAssertEqual(Array(block[8...11]), [0x02, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(block[56...59]), [0, 0, 0, 0], "light 14 is not a key")
        XCTAssertEqual(Array(block[492...495]), [123, 0, 0, 0])
        XCTAssertEqual(Array(block[574...575]), [0xaa, 0x55])
        XCTAssertEqual(block.enumerated().filter { $0.offset % 4 == 0 && $0.element != 0 }.count, 104)
    }

    func testParsesStoredColoursFromTheReadbackBlock() {
        var block = [UInt8](repeating: 0, count: 576)
        for slot in 0..<144 { block[4 * slot] = UInt8(slot) }
        block[5] = 0xfc

        let colors = PerKeyProtocol.colors(fromBlock: block)

        XCTAssertEqual(colors?.count, 104)
        XCTAssertEqual(colors?[1], RGBColor(red: 0xfc, green: 0, blue: 0))
        XCTAssertEqual(colors?[2], black)
        XCTAssertNil(PerKeyProtocol.colors(fromBlock: Array(block.prefix(512))))
        XCTAssertEqual(Array(PerKeyProtocol.readRequest[1...9]), [0x04, 0xf5, 0, 0, 0, 0, 0, 0, 9])
    }

    func testVerificationToleratesQuantisationButCatchesWrongLights() {
        let dim = RGBColor(red: 0, green: 0, blue: 4)
        let expected: [UInt8: RGBColor] = [1: red, 2: black, 3: dim]
        var readBack: [UInt8: RGBColor] = [1: RGBColor(red: 0xfc, green: 0, blue: 0), 2: black, 3: black]

        XCTAssertEqual(PerKeyVerification.mismatchedLights(expected: expected, readBack: readBack), [])

        readBack[1] = RGBColor(red: 0, green: 0xfc, blue: 0)
        readBack[2] = RGBColor(red: 0x40, green: 0, blue: 0)
        XCTAssertEqual(PerKeyVerification.mismatchedLights(expected: expected, readBack: readBack), [1, 2])
    }

    func testRequestMergesOntoStoredColoursUnlessCleared() {
        let green = RGBColor(red: 0, green: 0xff, blue: 0)
        let blue = RGBColor(red: 0, green: 0, blue: 0xff)
        var stored = Dictionary(uniqueKeysWithValues: KeyboardLayout.keys.map { ($0.light, black) })
        stored[1] = red
        stored[2] = green

        let merged = PerKeyColorRequest(keys: [2: blue]).resolve(stored: stored)
        XCTAssertEqual(merged[1], red)
        XCTAssertEqual(merged[2], blue)
        XCTAssertEqual(merged.count, 104)

        let cleared = PerKeyColorRequest(clear: true, keys: [2: blue]).resolve(stored: stored)
        XCTAssertEqual(cleared[1], black)
        XCTAssertEqual(cleared[2], blue)

        let filled = PerKeyColorRequest(all: green, keys: [1: blue]).resolve(stored: stored)
        XCTAssertEqual(filled[1], blue)
        XCTAssertEqual(filled[123], green)
        XCTAssertEqual(filled.count, 104)
    }

    func testParsesKeyColourCommands() throws {
        XCTAssertEqual(try AK35iCommandParser.parse(["keys", "list"]), .perKeyList)
        XCTAssertEqual(
            try AK35iCommandParser.parse(["keys", "set", "Esc=ff0000", "num1=00FF00", "--brightness", "3"]),
            .perKeySet(PerKeyColorRequest(brightness: 3, keys: [1: red, 86: RGBColor(red: 0, green: 0xff, blue: 0)]), apply: false)
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["keys", "set", "--clear", "--all", "0000ff", "--apply"]),
            .perKeySet(PerKeyColorRequest(clear: true, all: RGBColor(red: 0, green: 0, blue: 0xff)), apply: true)
        )
    }

    func testRejectsMalformedKeyColourCommandsBeforeTouchingTheDevice() {
        for arguments in [
            ["keys", "set"],
            ["keys", "set", "--apply"],
            ["keys", "set", "F13=ff0000"],
            ["keys", "set", "Esc=red"],
            ["keys", "set", "Esc"],
            ["keys", "set", "Esc=ff0000", "esc=00ff00"],
            ["keys", "set", "--all"],
        ] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)") { error in
                guard case .invalidUsage = error as? AK35iCommandError else {
                    return XCTFail("\(arguments): \(error)")
                }
            }
        }
        XCTAssertThrowsError(try AK35iCommandParser.parse(["keys", "set", "Esc=ff0000", "--brightness", "6"])) { error in
            XCTAssertEqual(error as? LightingEffectError, .outOfRange(.brightness, value: 6, allowed: Array(0...5)))
        }
    }
}
