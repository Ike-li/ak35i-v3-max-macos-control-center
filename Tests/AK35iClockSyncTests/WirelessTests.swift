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

    /// The data carried by a stream, in order, and each packet's header.
    private func streamed(_ packets: [[UInt8]]) -> (headers: [[UInt8]], data: [UInt8]) {
        (packets.map { Array($0[0...2]) }, packets.flatMap { $0[3..<31] })
    }

    private func wiredBlock(_ packets: [FeaturePacket]) -> [UInt8] {
        packets.dropFirst(2).filter { !$0.expectsAck }.flatMap { $0.report.dropFirst() }
    }

    /// DeviceDriver.exe 0x418e30; firmware 0x6AD8 / 0x6B0C write P[3..30] to
    /// 0x9400 / 0xAC00 + 28 × P[2], erasing the page at its first byte.
    func testKeymapLayersStreamTheWiredBlockInTwentyOnePackets() {
        let assignments: [UInt8: KeyAction] = [3: .disabled, 30: .media(.mute)]
        for (layer, command) in [(KeymapLayer.base, UInt8(0x10)), (.fn, 0x12)] {
            let packets = KeymapProtocol.wirelessPackets(layer: layer, assignments: assignments)
            let (headers, data) = streamed(packets)
            XCTAssertEqual(packets.count, 21)
            XCTAssertLessThanOrEqual(packets.count * 28, 1024, "stays inside one flash page")
            XCTAssertEqual(headers.first, [command, 0x1c, 0])
            XCTAssertEqual(headers.last, [command, 0x10, 20])
            XCTAssertEqual(Array(data.prefix(576)), wiredBlock(KeymapProtocol.packets(layer: layer, assignments: assignments)))
            XCTAssertTrue(data.dropFirst(576).allSatisfy { $0 == 0 })
            XCTAssertTrue(packets.allSatisfy { $0[31] == checksum($0) })
        }
    }

    /// DeviceDriver.exe 0x44ca60: custom mode first, then 21 × `14` into 0x9C00.
    func testPerKeyColoursSwitchToCustomModeThenStreamTheWiredBlock() {
        let colors: [UInt8: RGBColor] = [1: RGBColor(red: 0xff, green: 0, blue: 0)]
        let packets = PerKeyProtocol.wirelessPackets(colors: colors, brightness: 4)
        XCTAssertEqual(packets.count, 22)
        XCTAssertEqual(Array(packets[0][0...18]), [0x05, 0x10, 0x00, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0xaa, 0x55])
        let (headers, data) = streamed(Array(packets.dropFirst()))
        XCTAssertEqual(headers.first, [0x14, 0x1c, 0])
        XCTAssertEqual(headers.last, [0x14, 0x10, 20])
        XCTAssertEqual(Array(data.prefix(576)), wiredBlock(PerKeyProtocol.writePackets(colors: colors)))
    }

    /// DeviceDriver.exe 0x42e0f0: the wired table in 28-byte slices, with the
    /// driver's packet count rule, AA 55 at the end and E mod 28 as the last length.
    func testMacrosStreamTheWiredTable() throws {
        let macro = Macro(steps: [MacroStep(event: .keyDown(0x04), delay: 50), MacroStep(event: .keyUp(0x04), delay: 0)])
        let packets = try MacroProtocol.wirelessPackets(for: [macro])
        let (headers, data) = streamed(packets)
        // E = 0x190 + 8 + 16 = 424 = 15 × 28 + 4, so 15 + 2 packets.
        XCTAssertEqual(packets.count, 17)
        XCTAssertEqual(headers.first, [0x09, 0x1c, 0])
        XCTAssertEqual(headers.last, [0x09, UInt8(424 % 28), 16])
        XCTAssertEqual(Array(data[474...475]), [0xaa, 0x55])
        XCTAssertEqual(Array(data.prefix(424)), Array(wiredBlock(try MacroProtocol.packets(for: [macro])).prefix(424)))
        XCTAssertEqual(data.dropFirst(424).filter { $0 != 0 }, [0xaa, 0x55])

        XCTAssertEqual(try MacroProtocol.wirelessPackets(for: []).count, 400 / 28 + 2)
    }

    /// Packet 110 would reach 0xAC00 and erase the Fn layer, so the table may
    /// end at most at 3024 bytes (109 packets) although the wired limit is higher.
    func testRefusesMacroTablesThatWouldSpillIntoTheFnLayer() throws {
        func macro(steps: Int) -> Macro {
            Macro(steps: (0..<steps).map { MacroStep(event: $0 % 2 == 0 ? .keyDown(0x04) : .keyUp(0x04), delay: 10) })
        }
        XCTAssertEqual(try MacroProtocol.wirelessPackets(for: [macro(steps: 327)]).count, 109)
        XCTAssertNoThrow(try MacroProtocol.packets(for: [macro(steps: 328)]))
        XCTAssertThrowsError(try MacroProtocol.wirelessPackets(for: [macro(steps: 328)])) { error in
            XCTAssertEqual(error as? MacroError, .tooLargeForWireless(bytes: 3032))
        }
    }

    func testReceiverSnapshotOffersOnlyWhatWorksOverTwoPointFourGigahertz() {
        let snapshot = AK35iDeviceSnapshot.wireless
        XCTAssertEqual(snapshot.connection, .wireless)
        for feature in [AK35iFeature.clock, .battery, .lighting, .systemSettings, .perKeyLighting, .keymap, .macros] {
            XCTAssertEqual(snapshot.capability(feature).state, .experimental, "\(feature)")
        }
        XCTAssertEqual(snapshot.capability(.screenUpload).state, .notConnected)
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
