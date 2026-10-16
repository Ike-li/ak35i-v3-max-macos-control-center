import XCTest
@testable import AK35iClockSync

final class KeymapTests: XCTestCase {
    func testKeyUsagesComeFromTheDriverLayout() {
        XCTAssertEqual(KeyboardLayout.key(named: "Esc")?.usage, 0x29)
        XCTAssertEqual(KeyboardLayout.key(named: "capslock")?.usage, 0x39)
        XCTAssertEqual(KeyboardLayout.key(named: "NumEnter")?.usage, 0x58)
        XCTAssertEqual(KeyboardLayout.key(named: "LWin")?.usage, 0xe3)
        XCTAssertEqual(KeyboardLayout.key(named: "Fn")?.usage, 0xaf)
        XCTAssertEqual(Set(KeyboardLayout.keys.map(\.usage)).count, 104)
    }

    /// Record encodings of DeviceDriver.exe 0x4186d2–0x418bd3.
    func testEncodesActionsLikeTheDriver() {
        XCTAssertEqual(KeyAction.defaultKey.record, [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(KeyAction.disabled.record, [0x05, 0x03, 0x00, 0x00])
        XCTAssertEqual(KeyAction.key(modifiers: 0, usage: 0x29).record, [0x02, 0x00, 0x29, 0x00])
        XCTAssertEqual(KeyAction.key(modifiers: 0x01, usage: 0x06).record, [0x02, 0x01, 0x06, 0x00])
        XCTAssertEqual(KeyAction.key(modifiers: 0, usage: 0xe0).record, [0x02, 0x01, 0x00, 0x00])
        XCTAssertEqual(KeyAction.key(modifiers: 0, usage: 0xe6).record, [0x02, 0x40, 0x00, 0x00])
        XCTAssertEqual(KeyAction.media(.mute).record, [0x03, 0xe2, 0x00, 0x00])
        XCTAssertEqual(KeyAction.media(.playPause).record, [0x03, 0xcd, 0x00, 0x00])
        XCTAssertEqual(KeyAction.mouse(.middle).record, [0x01, 0x01, 0x04, 0x00])
        XCTAssertEqual(KeyAction.mouse(.wheelDown).record, [0x01, 0x03, 0xff, 0x00])
    }

    func testWritesTheWholeLayerLikeTheDriver() {
        let capsLock = KeyboardLayout.light(named: "CapsLock")!
        let packets = KeymapProtocol.packets(layer: .base, assignments: [capsLock: .key(modifiers: 0, usage: 0x29)])
        let block = packets[2...10].flatMap { $0.report.dropFirst() }

        XCTAssertEqual(packets.count, 13)
        XCTAssertEqual(packets.map(\.expectsAck), [true, true] + Array(repeating: false, count: 9) + [true, true])
        XCTAssertEqual(Array(packets[0].report[1...2]), [0x04, 0x18])
        XCTAssertEqual(Array(packets[1].report[1...9]), [0x04, 0x11, 0, 0, 0, 0, 0, 0, 9])
        XCTAssertEqual(Array(packets[11].report[1...2]), [0x04, 0x02])
        XCTAssertEqual(Array(packets[12].report[1...2]), [0x04, 0xf0])
        XCTAssertEqual(block.count, 576)
        XCTAssertEqual(Array(block[220...223]), [0x02, 0x00, 0x29, 0x00])
        XCTAssertEqual(Array(block[574...575]), [0xaa, 0x55])
        XCTAssertEqual(block.filter { $0 != 0 }.count, 4)

        let fnLayer = KeymapProtocol.packets(layer: .fn, assignments: [:])
        XCTAssertEqual(Array(fnLayer[1].report[1...9]), [0x04, 0x27, 0, 0, 0, 0, 0, 0, 9])
        XCTAssertEqual(fnLayer[2...10].flatMap { $0.report.dropFirst() }.filter { $0 != 0 }, [0xaa, 0x55])
    }

    private func light(_ name: String) -> UInt8 { KeyboardLayout.light(named: name)! }

    func testParsesKeymapCommands() throws {
        XCTAssertEqual(
            try AK35iCommandParser.parse([
                "keymap", "set", "CapsLock=Esc", "a=Ctrl+Shift+C", "RAlt=Cmd", "F1=media:mute",
                "F2=mouse:wheelup", "Insert=disabled", "Menu=RCtrl", "--layer", "fn", "--apply",
            ]),
            .keymapSet(KeymapRequest(layer: .fn, assignments: [
                light("CapsLock"): .key(modifiers: 0, usage: 0x29),
                light("A"): .key(modifiers: 0x03, usage: 0x06),
                light("RAlt"): .key(modifiers: 0, usage: 0xe3),
                light("F1"): .media(.mute),
                light("F2"): .mouse(.wheelUp),
                light("Insert"): .disabled,
                light("Menu"): .key(modifiers: 0, usage: 0xe4),
            ]), apply: true)
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["keymap", "set", "Esc=default"]),
            .keymapSet(KeymapRequest(layer: .base, assignments: [light("Esc"): .defaultKey]), apply: false)
        )
        XCTAssertEqual(try AK35iCommandParser.parse(["keymap", "reset"]), .keymapReset([.base, .fn], apply: false))
        XCTAssertEqual(try AK35iCommandParser.parse(["keymap", "reset", "--layer", "base", "--apply"]), .keymapReset([.base], apply: true))
    }

    func testRejectsKeymapsTheDriverWouldNotSendOrThatLockOutFn() {
        for arguments in [
            ["keymap", "set"],
            ["keymap", "set", "--apply"],
            ["keymap", "set", "Fn=Esc"],
            ["keymap", "set", "CapsLock=Fn"],
            ["keymap", "set", "CapsLock=Ctrl+Shift"],
            ["keymap", "set", "CapsLock=Ctrl+LShift"],
            ["keymap", "set", "CapsLock=Esc+A"],
            ["keymap", "set", "CapsLock=F13"],
            ["keymap", "set", "CapsLock=media:launch"],
            ["keymap", "set", "CapsLock=mouse:double"],
            ["keymap", "set", "CapsLock=Esc", "capslock=Tab"],
            ["keymap", "set", "CapsLock"],
            ["keymap", "set", "CapsLock=Esc", "--layer", "top"],
            ["keymap", "reset", "--layer"],
        ] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)") { error in
                guard case .invalidUsage = error as? AK35iCommandError else {
                    return XCTFail("\(arguments): \(error)")
                }
            }
        }
    }

    func testEditorKeepsOneAssignmentSetPerLayerAndWritesWhatItShows() {
        var editor = KeymapEditorState()
        editor.selection = light("CapsLock")
        XCTAssertTrue(editor.assign(.key(modifiers: 0, usage: 0x29)))

        editor.layer = .fn
        editor.selection = light("F1")
        XCTAssertTrue(editor.assign(.media(.mute)))
        editor.selection = light("Fn")
        XCTAssertFalse(editor.assign(.disabled), "Fn itself must stay reachable")

        XCTAssertEqual(editor.request(), KeymapRequest(layer: .fn, assignments: [light("F1"): .media(.mute)]))
        editor.layer = .base
        XCTAssertEqual(editor.request(), KeymapRequest(layer: .base, assignments: [light("CapsLock"): .key(modifiers: 0, usage: 0x29)]))

        editor.selection = light("CapsLock")
        XCTAssertTrue(editor.assign(.defaultKey))
        XCTAssertEqual(editor.request(), KeymapRequest(layer: .base))
        XCTAssertNil(editor.action(for: light("CapsLock")))
    }

    func testDisplayNamesParseBackToTheSameAction() {
        let actions: [KeyAction] = [
            .defaultKey, .disabled,
            .key(modifiers: 0, usage: 0x29), .key(modifiers: 0x0b, usage: 0x06), .key(modifiers: 0, usage: 0xe4),
        ] + MediaKey.allCases.map(KeyAction.media) + MouseAction.allCases.map(KeyAction.mouse)
        for action in actions {
            XCTAssertEqual(KeyAction(target: action.displayName), action, action.displayName)
        }
    }
}
