import XCTest
@testable import AK35iClockSync

final class ClockProtocolTests: XCTestCase {
    func testDeviceSnapshotRedactsSerialNumbers() {
        let snapshot = AK35iDeviceSnapshot.from(interfaces: [
            HIDInterfaceSnapshot(
                usagePage: 0xff13,
                usage: 0x0001,
                maxFeatureReportSize: 64,
                maxOutputReportSize: 64,
                serialNumber: "private-device-serial"
            ),
        ])

        XCTAssertNil(snapshot.serialNumber)
        XCTAssertTrue(snapshot.channels.allSatisfy { $0.interface.serialNumber == nil })
    }

    func testDiscoveryOnlyMatchesVendorControlCollections() {
        XCTAssertEqual(
            AK35iHIDDeviceDiscovery.discoveryCollections,
            [
                AK35iHIDUsage(usagePage: 0xff13, usage: 0x0001),
                AK35iHIDUsage(usagePage: 0xff68, usage: 0x0061),
            ]
        )
        XCTAssertFalse(
            AK35iHIDDeviceDiscovery.discoveryCollections.contains(
                AK35iHIDUsage(usagePage: 0x0001, usage: 0x0006)
            )
        )
    }

    func testClassifiesActualVendorHIDCollectionsWithoutGuessingWritableFeatures() {
        let snapshot = AK35iDeviceSnapshot.from(interfaces: [
            HIDInterfaceSnapshot(usagePage: 0xff13, usage: 0x0001, maxFeatureReportSize: 64, maxOutputReportSize: 64),
            HIDInterfaceSnapshot(usagePage: 0x000c, usage: 0x0001, maxFeatureReportSize: 1, maxOutputReportSize: 1),
            HIDInterfaceSnapshot(usagePage: 0x0001, usage: 0x0006, maxFeatureReportSize: 0, maxOutputReportSize: 1),
            HIDInterfaceSnapshot(usagePage: 0xff68, usage: 0x0061, maxFeatureReportSize: 0, maxOutputReportSize: 4096),
        ])

        XCTAssertEqual(snapshot.connection, .usbWired)
        XCTAssertEqual(snapshot.channels.map(\.kind), [.clockAndSettings, .screenTransfer])
        XCTAssertEqual(snapshot.capability(.clock).state, .verified)
        XCTAssertEqual(snapshot.capability(.screenUpload).state, .captureRequired)
        XCTAssertEqual(snapshot.capability(.lighting).state, .captureRequired)
        XCTAssertEqual(snapshot.capability(.keymap).state, .captureRequired)
        XCTAssertEqual(snapshot.capability(.macros).state, .captureRequired)
    }

    func testParsesSafeCLICommandsAndRejectsUnknownWrites() throws {
        XCTAssertEqual(
            try AK35iCommandParser.parse(["time", "sync", "--utc8", "--dry-run"]),
            .timeSync(timeZone: .utcPlusEight, apply: false)
        )
        XCTAssertEqual(
            try AK35iCommandParser.parse(["preview", "time", "--utc8"]),
            .previewTime(timeZone: .utcPlusEight)
        )
        XCTAssertThrowsError(try AK35iCommandParser.parse(["apply", "screen", "avatar.gif"])) { error in
            XCTAssertEqual(error as? AK35iCommandError, .featureRequiresCapture(.screenUpload))
        }
    }

    func testFinderLaunchArgumentOpensTheGraphicalControlCenter() throws {
        XCTAssertEqual(
            try AK35iLaunchContext.command(from: ["-psn_0_123456"]),
            .gui
        )
        XCTAssertEqual(
            try AK35iLaunchContext.command(from: ["-psn_0_123456", "status"]),
            .status(json: false)
        )
    }

    func testAppBundleLaunchWithoutFinderProcessSerialStillOpensTheControlCenter() throws {
        XCTAssertEqual(
            try AK35iLaunchContext.command(
                from: [],
                executablePath: "/Applications/AK35i Control Center.app/Contents/MacOS/ak35i"
            ),
            .gui
        )
        XCTAssertEqual(
            try AK35iLaunchContext.command(from: [], executablePath: "/usr/local/bin/ak35i"),
            .help
        )
    }

    func testAutoSyncLaunchAgentRunsOnlyAfterExplicitEnablement() throws {
        let plan = AutoSyncLaunchAgentPlan(executablePath: "/Applications/AK35i Control Center.app/Contents/MacOS/ak35i")
        let data = try plan.propertyListData()
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["Label"] as? String, AutoSyncLaunchAgentPlan.label)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["StartInterval"] as? Int, 86_400)
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/Applications/AK35i Control Center.app/Contents/MacOS/ak35i", "time", "sync", "--utc8", "--apply"]
        )
    }

    func testBackupNeverClaimsToReadUnverifiedDeviceSettings() {
        XCTAssertEqual(
            SafetyGate.backupAvailability(for: .screenUpload),
            .unavailable("屏幕内容尚无经验证的硬件读取协议，不能伪造备份。")
        )
        XCTAssertEqual(
            SafetyGate.backupAvailability(for: .clock),
            .notNeeded("时钟同步是一次性写入，不存在可导出的板载时钟配置。")
        )
    }

    func testBuildsKnownFirmwareRtcSequence() {
        let reports = ClockProtocol.reports(for: ClockTime(
            year: 2026,
            month: 7,
            day: 26,
            hour: 18,
            minute: 45,
            second: 30,
            weekday: 0
        ))

        XCTAssertEqual(reports.count, 4)
        XCTAssertTrue(reports.allSatisfy { $0.count == 65 })
        XCTAssertEqual(Array(reports[0][0...9]), [0, 4, 0x18, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(reports[1][0...10]), [0, 4, 0x28, 0, 0, 0, 0, 0, 0, 1, 0])
        XCTAssertEqual(Array(reports[2][0...11]), [0, 0, 1, 0x5a, 26, 7, 26, 18, 45, 30, 0, 0])
        XCTAssertEqual(Array(reports[2][63...64]), [0xaa, 0x55])
        XCTAssertEqual(Array(reports[3][0...9]), [0, 4, 2, 0, 0, 0, 0, 0, 0, 0])
    }

    func testClampsOutOfRangeYearToFirmwareByteRange() {
        let before2000 = ClockProtocol.reports(for: ClockTime(year: 1999, month: 1, day: 1, hour: 0, minute: 0, second: 0, weekday: 4))
        let after2255 = ClockProtocol.reports(for: ClockTime(year: 2256, month: 1, day: 1, hour: 0, minute: 0, second: 0, weekday: 4))

        XCTAssertEqual(before2000[2][4], 0)
        XCTAssertEqual(after2255[2][4], 0xff)
    }

    func testMacOSHidTransportStripsUnnumberedReportPrefix() {
        let reports = ClockProtocol.reports(for: ClockTime(
            year: 2026,
            month: 7,
            day: 26,
            hour: 19,
            minute: 2,
            second: 44,
            weekday: 0
        ))

        let startPayload = HIDFeatureReport.macOSPayload(from: reports[0])
        let dataPayload = HIDFeatureReport.macOSPayload(from: reports[2])

        XCTAssertEqual(startPayload.count, 64)
        XCTAssertEqual(Array(startPayload[0...1]), [4, 0x18])
        XCTAssertEqual(dataPayload.count, 64)
        XCTAssertEqual(Array(dataPayload[0...9]), [0, 1, 0x5a, 26, 7, 26, 19, 2, 44, 0])
        XCTAssertEqual(Array(dataPayload[62...63]), [0xaa, 0x55])
    }

    func testBuildsClockTimeInFixedUTCPlusEight() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-27T00:30:45Z"))
        let utcPlusEight = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))

        let time = ClockTime.from(instant, timeZone: utcPlusEight)

        XCTAssertEqual(time, ClockTime(
            year: 2026,
            month: 7,
            day: 27,
            hour: 8,
            minute: 30,
            second: 45,
            weekday: 1
        ))
    }
}
