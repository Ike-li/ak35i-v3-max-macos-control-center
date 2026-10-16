import XCTest
@testable import AK35iClockSync

final class MacroTests: XCTestCase {
    private func block(_ packets: [FeaturePacket]) -> [UInt8] {
        packets.dropFirst(2).dropLast().flatMap { $0.report.dropFirst() }
    }

    /// One macro: A down, 50 ms, A up, 0 ms (raised to the driver's 10 ms).
    func testEncodesTheMacroTableLikeTheDriver() throws {
        let macro = Macro(steps: [
            MacroStep(event: .keyDown(0x04), delay: 50),
            MacroStep(event: .keyUp(0x04), delay: 0),
        ])
        let packets = try MacroProtocol.packets(for: [macro])
        let data = block(packets)

        XCTAssertEqual(packets.map(\.expectsAck), [true, true] + Array(repeating: false, count: 8) + [true])
        XCTAssertEqual(Array(packets[0].report[1...2]), [0x04, 0x19])
        XCTAssertEqual(Array(packets[1].report[1...9]), [0x04, 0x15, 0, 0, 0, 0, 0, 0, 8])
        XCTAssertEqual(Array(packets.last!.report[1...2]), [0x04, 0x02])
        XCTAssertEqual(packets.last!.settleTime, 0.065, accuracy: 0.0001)
        XCTAssertEqual(data.count, 512)
        XCTAssertEqual(Array(data[0...7]), [0x90, 0x01, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(data[0x190..<0x1a8]), [
            0x04, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0x04, 0xb0, 0x32, 0, 0, 0x50,
            0, 0, 0x04, 0x30, 0x0a, 0, 0, 0x50,
        ])
        XCTAssertEqual(Array(data[510...511]), [0xaa, 0x55])
        XCTAssertEqual(data.filter { $0 != 0 }.count, 2 + 1 + 8 + 2)
    }

    func testEmptyTableClearsEveryMacro() throws {
        let packets = try MacroProtocol.packets(for: [])
        let data = block(packets)

        XCTAssertEqual(packets[1].report[9], 8)
        XCTAssertEqual(data.count, 512)
        XCTAssertEqual(data.filter { $0 != 0 }, [0xaa, 0x55])
        XCTAssertEqual(Array(data[510...511]), [0xaa, 0x55])
    }

    /// The driver adds a whole chunk when the table ends on a 64-byte boundary.
    func testAddsAChunkWhenTheTableEndsOnABoundary() throws {
        let steps = [0x04, 0x05].flatMap { [MacroStep(event: .keyDown($0), delay: 10), MacroStep(event: .keyUp($0), delay: 10)] }
            + [MacroStep(event: .keyDown(0x06), delay: 10)]
        let packets = try MacroProtocol.packets(for: [Macro(steps: steps)])

        XCTAssertEqual(packets[1].report[9], 8, "table ends at 448 = 7 × 64")
        XCTAssertEqual(Array(block(packets)[510...511]), [0xaa, 0x55])
    }

    func testIndexesEachMacroAndEncodesMouseButtons() throws {
        let first = Macro(steps: [MacroStep(event: .keyDown(0xe1), delay: 10), MacroStep(event: .keyUp(0xe1), delay: 70_000)])
        let second = Macro(steps: [
            MacroStep(event: .mouseDown(.middle), delay: 10), MacroStep(event: .mouseUp(.middle), delay: 10),
            MacroStep(event: .mouseDown(.right), delay: 10), MacroStep(event: .mouseUp(.right), delay: 10),
        ])
        let data = block(try MacroProtocol.packets(for: [first, second]))

        XCTAssertEqual(Array(data[0...7]), [0x90, 0x01, 0, 0, 0xa8, 0x01, 0, 0])
        XCTAssertEqual(Array(data[0x198..<0x19c]), [0, 0, 0xe1, 0xb0])
        XCTAssertEqual(Array(data[0x1a4..<0x1a8]), [0x70, 0x11, 0, 0x50], "70000 ms keeps only its low 16 bits")
        XCTAssertEqual(Array(data[0x1a8..<0x1b0]), [0x08, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(data[0x1b0..<0x1b8]), [0, 0, 0x04, 0x90, 0x0a, 0, 0, 0x50])
        XCTAssertEqual(Array(data[0x1b8..<0x1bc]), [0, 0, 0x04, 0x10])
        XCTAssertEqual(Array(data[0x1c0..<0x1c4]), [0, 0, 0x02, 0x90])
    }

    func testRejectsTablesTheDriverWouldNotSend() {
        let tap = Macro(steps: [MacroStep(event: .keyDown(0x04), delay: 10), MacroStep(event: .keyUp(0x04), delay: 10)])
        XCTAssertThrowsError(try MacroProtocol.packets(for: Array(repeating: tap, count: 101))) { error in
            XCTAssertEqual(error as? MacroError, .tooManyMacros(101))
        }
        let long = Macro(steps: Array(repeating: tap.steps, count: 168).flatMap { $0 })
        XCTAssertNoThrow(try MacroProtocol.packets(for: [long]), "8 × (336 + 1) = 2696 fits")
        let longer = Macro(steps: long.steps + tap.steps)
        XCTAssertThrowsError(try MacroProtocol.packets(for: [longer])) { error in
            XCTAssertEqual(error as? MacroError, .tooManyEvents(events: 338, macros: 1))
        }
    }

    func testMacroKeysCarryIndexPlaybackAndCount() {
        XCTAssertEqual(KeyAction.macro(index: 0, playback: .once).record, [0x06, 0x00, 0x00, 0x00])
        XCTAssertEqual(KeyAction.macro(index: 1, playback: .times(3)).record, [0x06, 0x01, 0x01, 0x03])
        XCTAssertEqual(KeyAction.macro(index: 2, playback: .untilPressedAgain).record, [0x06, 0x02, 0x02, 0x00])
        XCTAssertEqual(KeyAction.macro(index: 3, playback: .whileHeld).record, [0x06, 0x03, 0x03, 0x00])
    }

    private func tap(_ usage: UInt8, _ delay: Int = Macro.defaultDelay) -> [MacroStep] {
        [MacroStep(event: .keyDown(usage), delay: Macro.defaultDelay), MacroStep(event: .keyUp(usage), delay: delay)]
    }

    func testParsesMacroScripts() throws {
        XCTAssertEqual(try Macro(script: "A"), Macro(steps: tap(0x04)))
        XCTAssertEqual(try Macro(script: "Cmd+Space, 100ms, a"), Macro(steps: [
            MacroStep(event: .keyDown(0xe3), delay: Macro.defaultDelay),
            MacroStep(event: .keyDown(0x2c), delay: Macro.defaultDelay),
            MacroStep(event: .keyUp(0x2c), delay: Macro.defaultDelay),
            MacroStep(event: .keyUp(0xe3), delay: 100),
        ] + tap(0x04)))
        XCTAssertEqual(try Macro(script: "+LShift,B,-LShift"), Macro(steps: [
            MacroStep(event: .keyDown(0xe1), delay: Macro.defaultDelay),
        ] + tap(0x05) + [
            MacroStep(event: .keyUp(0xe1), delay: Macro.defaultDelay),
        ]))
        XCTAssertEqual(try Macro(script: "mouse:left"), Macro(steps: [
            MacroStep(event: .mouseDown(.left), delay: Macro.defaultDelay),
            MacroStep(event: .mouseUp(.left), delay: Macro.defaultDelay),
        ]))
        XCTAssertEqual(try Macro(script: "A").script, "A")
        XCTAssertEqual(try Macro(script: "Cmd+Space, 100ms, a").script, "+LWin, Space, -LWin, 100ms, A")
    }

    func testRejectsScriptsThatWouldLeaveKeysHeldOrCannotBeSent() {
        for script in ["", " , ", "50ms", "A, 5ms", "A, 70000ms", "+A", "-A", "+A, +A, -A", "Fn", "F13", "mouse:back", "Ctrl+Shift", "A+B"] {
            XCTAssertThrowsError(try Macro(script: script), script)
        }
    }

    func testParsesMacroCommandsAndMacroKeys() throws {
        XCTAssertEqual(
            try AK35iCommandParser.parse(["macro", "set", "A", "Cmd+Space", "--apply"]),
            .macroSet([try Macro(script: "A"), try Macro(script: "Cmd+Space")], apply: true)
        )
        XCTAssertEqual(try AK35iCommandParser.parse(["macro", "clear"]), .macroSet([], apply: false))
        XCTAssertThrowsError(try AK35iCommandParser.parse(["macro", "set"]))
        XCTAssertThrowsError(try AK35iCommandParser.parse(["macro", "set", "+A"]))

        XCTAssertEqual(KeyAction(target: "macro:1"), .macro(index: 0, playback: .once))
        XCTAssertEqual(KeyAction(target: "macro:2:x3"), .macro(index: 1, playback: .times(3)))
        XCTAssertEqual(KeyAction(target: "MACRO:100:toggle"), .macro(index: 99, playback: .untilPressedAgain))
        XCTAssertEqual(KeyAction(target: "macro:5:hold"), .macro(index: 4, playback: .whileHeld))
        for target in ["macro:0", "macro:101", "macro:1:x0", "macro:1:x256", "macro:1:tap", "macro:"] {
            XCTAssertNil(KeyAction(target: target), target)
        }
        let action = KeyAction.macro(index: 1, playback: .times(3))
        XCTAssertEqual(KeyAction(target: action.displayName), action)
    }
}
