import XCTest
@testable import AK35iClockSync

/// The SDK also exposes QuickDraw's RGBColor.
private typealias RGBColor = AK35iClockSync.RGBColor

/// Stands in for the 2.4G receiver: echoes every packet unless told to stay silent.
private final class FakeReceiver: WirelessExchanging {
    var sent: [[UInt8]] = []
    var silentAt: Int?

    func exchange(_ report: [UInt8], timeout: TimeInterval) throws -> [UInt8]? {
        sent.append(report)
        if sent.count - 1 == silentAt { return nil }
        return Array(report.prefix(3)) + Array(repeating: 0, count: 29)
    }
}

final class WirelessTests: XCTestCase {
    private func checksum(_ packet: [UInt8]) -> UInt8 {
        packet[0..<31].reduce(0, &+)
    }

    func testPacketsEndWithTheirByteSum() {
        let packet = WirelessProtocol.packet(0x09, length: 0x1c, sequence: 2, data: [1, 2, 3])
        XCTAssertEqual(packet.count, 32)
        XCTAssertEqual(Array(packet[0...5]), [0x09, 0x1c, 0x02, 1, 2, 3])
        XCTAssertTrue(packet[6..<31].allSatisfy { $0 == 0 })
        XCTAssertEqual(packet[31], 0x09 + 0x1c + 0x02 + 1 + 2 + 3)
        XCTAssertEqual(BatteryProtocol.request, WirelessProtocol.packet(0x20, length: 0x01, data: []))
        XCTAssertEqual(WirelessProtocol.probe, WirelessProtocol.packet(0x02, length: 0x00, data: []))
    }

    /// DeviceDriver.exe 0x423bf0; firmware 0x6A78 reads bytes 5–11.
    func testClockIsOnePacketShiftedFromTheWiredDataFrame() {
        let time = ClockTime(year: 2026, month: 10, day: 16, hour: 9, minute: 30, second: 45, weekday: 5)
        let packet = ClockProtocol.wirelessPacket(for: time)
        XCTAssertEqual(Array(packet[0...18]), [0x0c, 0x10, 0x00, 0x00, 0x01, 0x5a, 26, 10, 16, 9, 30, 45, 0x00, 5, 0, 0, 0, 0xaa, 0x55])
        XCTAssertTrue(packet[19..<31].allSatisfy { $0 == 0 })
        XCTAssertEqual(packet[31], checksum(packet))
    }

    /// DeviceDriver.exe 0x42b5a0; firmware 0x68A6 stores p3–p18 like the wired frame.
    func testLightingIsOnePacketWithTheWiredFrame() throws {
        let red = try LightingEffect(mode: .staticColor, brightness: 4, color: .solid(RGBColor(red: 0xff, green: 0, blue: 0)))
        let packet = LightingProtocol.wirelessPacket(for: red)
        XCTAssertEqual(Array(packet[0...18]), [0x05, 0x10, 0x00, 0x01, 0xff, 0x00, 0x00, 0, 0, 0, 0, 0x00, 4, 3, 0, 0, 0, 0xaa, 0x55])
        XCTAssertEqual(packet[31], checksum(packet))

        let off = LightingProtocol.wirelessPacket(for: try LightingEffect(mode: .off))
        XCTAssertEqual(Array(off[0...18]), [0x05, 0x10, 0x00, 0x00] + Array(repeating: 0, count: 13) + [0xaa, 0x55])
    }

    /// DeviceDriver.exe 0x414260; firmware 0x6972 stores 28 bytes at 0x9000.
    func testSystemSettingsAreOnePacketWithTheWiredFrame() {
        XCTAssertEqual(
            Array(SystemSettingsProtocol.wirelessPacket(for: SystemSettings())[0...18]),
            [0x07, 0x10, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0x02, 0x00, 0x02, 0, 0, 0, 0, 0, 0xaa, 0x55]
        )
        var settings = SystemSettings()
        settings.disableAltTab = true
        settings.disableAltF4 = true
        settings.disableWin = true
        settings.fnSwitch = 1
        settings.sleep = .never
        settings.responseLevel = 5
        let packet = SystemSettingsProtocol.wirelessPacket(for: settings)
        XCTAssertEqual(Array(packet[3...11]), [0x00, 0x01, 1, 1, 1, 1, SleepTimeout.never.rawValue, 0x00, 5])
        XCTAssertEqual(packet[31], checksum(packet))
    }

    func testReceiverSnapshotOffersOnlyWhatWorksOverTwoPointFourGigahertz() {
        let snapshot = AK35iDeviceSnapshot.wireless
        XCTAssertEqual(snapshot.connection, .wireless)
        for feature in [AK35iFeature.clock, .battery, .lighting, .systemSettings] {
            XCTAssertEqual(snapshot.capability(feature).state, .experimental, "\(feature)")
        }
        for feature in [AK35iFeature.perKeyLighting, .screenUpload, .keymap, .macros] {
            XCTAssertEqual(snapshot.capability(feature).state, .notConnected, "\(feature)")
        }
    }

    func testWritesNothingWhenTheKeyboardDoesNotAnswer() {
        let receiver = FakeReceiver()
        receiver.silentAt = 0
        XCTAssertThrowsError(try WirelessSender.send([ClockProtocol.wirelessPacket(for: ClockTime(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0, weekday: 4))], over: receiver)) { error in
            XCTAssertEqual(error as? WirelessError, .keyboardOffline)
        }
        XCTAssertEqual(receiver.sent, [WirelessProtocol.probe])
    }

    func testStopsAtTheFirstPacketWithoutAnEcho() {
        let packets = (0..<4).map { WirelessProtocol.packet(0x10, length: 0x1c, sequence: UInt8($0), data: []) }
        let receiver = FakeReceiver()
        receiver.silentAt = 2
        XCTAssertThrowsError(try WirelessSender.send(packets, over: receiver)) { error in
            XCTAssertEqual(error as? WirelessError, .noReply(packet: 2, of: 4))
        }
        XCTAssertEqual(receiver.sent, [WirelessProtocol.probe, packets[0], packets[1]])

        let complete = FakeReceiver()
        var progress: [Int] = []
        XCTAssertNoThrow(try WirelessSender.send(packets, over: complete) { progress.append($0) })
        XCTAssertEqual(complete.sent, [WirelessProtocol.probe] + packets)
        XCTAssertEqual(progress, [1, 2, 3, 4])
    }
}
