import XCTest
@testable import AK35iClockSync

final class SystemSettingsTests: XCTestCase {
    /// Sequence of DeviceDriver.exe 0x413ff0 with the driver's first-run defaults.
    func testDefaultSettingsMatchTheDriverFrame() {
        let packets = SystemSettingsProtocol.packets(for: SystemSettings())

        XCTAssertEqual(packets.map(\.expectsAck), [true, true, false, true])
        XCTAssertTrue(packets.allSatisfy { $0.report.count == 65 && $0.report[0] == 0 })
        XCTAssertEqual(Array(packets[0].report[1...2]), [0x04, 0x18])
        XCTAssertEqual(Array(packets[1].report[1...9]), [0x04, 0x17, 0x01, 0, 0, 0, 0, 0, 0x01])
        XCTAssertEqual(Array(packets[2].report[1...10]), [0x00, 0x01, 0, 0, 0, 0, 0x02, 0, 0x02, 0])
        XCTAssertEqual(Array(packets[2].report[63...64]), [0xaa, 0x55])
        XCTAssertTrue(packets[2].report[11...62].allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(packets[3].report[1...2]), [0x04, 0x02])
    }

    func testEachSettingLandsInItsDriverByte() {
        let settings = SystemSettings(
            disableAltTab: true,
            disableAltF4: false,
            disableWin: true,
            fnSwitch: 1,
            sleep: .thirtyMinutes,
            responseLevel: 5
        )

        let data = SystemSettingsProtocol.packets(for: settings)[2].report

        XCTAssertEqual(Array(data[1...10]), [0x00, 0x01, 1, 0, 1, 1, 3, 0, 5, 0])
    }

    func testParsesSystemSettingsCommands() throws {
        XCTAssertEqual(try AK35iCommandParser.parse(["system", "set"]), .systemSet(SystemSettings(), apply: false))
        XCTAssertEqual(
            try AK35iCommandParser.parse([
                "system", "set", "--disable-win", "on", "--disable-alt-tab", "on", "--disable-alt-f4", "off",
                "--fn-switch", "1", "--sleep", "1m", "--response", "4", "--apply",
            ]),
            .systemSet(
                SystemSettings(disableAltTab: true, disableWin: true, fnSwitch: 1, sleep: .oneMinute, responseLevel: 4),
                apply: true
            )
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["system", "set", "--sleep", "never"]),
            .systemSet(SystemSettings(sleep: .never), apply: false)
        )
    }

    func testRejectsSettingsTheDriverCannotSend() {
        for arguments in [
            ["system", "set", "--response", "0"],
            ["system", "set", "--response", "6"],
            ["system", "set", "--sleep", "10m"],
            ["system", "set", "--fn-switch", "2"],
            ["system", "set", "--disable-win", "yes"],
            ["system", "set", "--disable-win"],
            ["system", "set", "--sleep", "1m", "--sleep", "5m"],
            ["system", "set", "--volume", "3"],
        ] {
            XCTAssertThrowsError(try AK35iCommandParser.parse(arguments), "\(arguments)") { error in
                guard case .invalidUsage = error as? AK35iCommandError else {
                    return XCTFail("\(arguments): \(error)")
                }
            }
        }
    }
}
