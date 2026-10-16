import XCTest
@testable import AK35iClockSync

final class BatteryTests: XCTestCase {
    private func reply(_ head: [UInt8]) -> [UInt8] {
        head + Array(repeating: 0, count: BatteryProtocol.reportLength - head.count)
    }

    /// DeviceDriver.exe 0x435ea0 / 0x4501c0: `20 01`, zeros, and the byte sum last.
    func testRequestMatchesTheDriver() {
        let request = BatteryProtocol.request
        XCTAssertEqual(request.count, 32)
        XCTAssertEqual(Array(request[0...2]), [0x20, 0x01, 0x00])
        XCTAssertTrue(request[3..<31].allSatisfy { $0 == 0 })
        XCTAssertEqual(request[31], 0x21)
    }

    func testReadsThePercentageFromAnEchoedReply() {
        XCTAssertEqual(BatteryProtocol.level(from: reply([0x20, 0x01, 0x00, 87])), 87)
        XCTAssertEqual(BatteryProtocol.level(from: reply([0x20, 0x01, 0x00, 100])), 100)
        XCTAssertEqual(BatteryProtocol.level(from: reply([0x20, 0x01, 0x00, 0xc8])), 100, "the driver caps at 100")
    }

    func testIgnoresRepliesTheDriverIgnores() {
        XCTAssertNil(BatteryProtocol.level(from: reply([0x20, 0x01, 0x00, 0])), "zero is skipped by the driver")
        XCTAssertNil(BatteryProtocol.level(from: reply([0x05, 0x10, 0x00, 87])), "answer to another command")
        XCTAssertNil(BatteryProtocol.level(from: reply([0x20, 0x01, 0x01, 87])))
        XCTAssertNil(BatteryProtocol.level(from: [0x20, 0x01, 0x00]))
    }

    /// Interfaces seen on a Mac with the receiver and a Logitech receiver plugged in.
    func testPicksOnlyTheReceiversThirtyTwoByteVendorInterface() {
        let dongle = ReceiverInterface(vendorID: 0x05ac, productID: 0x024f, product: "2.4G Dongle", usagePage: 0xff60, usage: 0x61, maxOutputReportSize: 32)
        XCTAssertTrue(dongle.isBatteryChannel)
        XCTAssertTrue(ReceiverInterface(vendorID: 0x0c45, productID: 0xfdfd, product: nil, usagePage: 0xff60, usage: 0x61, maxOutputReportSize: 32).isBatteryChannel)

        var wider = dongle
        wider.maxOutputReportSize = 64
        XCTAssertFalse(wider.isBatteryChannel)
        var keyboard = dongle
        keyboard.usagePage = 0x01
        keyboard.usage = 0x06
        XCTAssertFalse(keyboard.isBatteryChannel)
        XCTAssertFalse(ReceiverInterface(vendorID: 0x046d, productID: 0xc539, product: "USB Receiver", usagePage: 0xff00, usage: 0x01, maxOutputReportSize: 32).isBatteryChannel)
        XCTAssertFalse(ReceiverInterface(vendorID: 0x046d, productID: 0xc539, product: "USB Receiver", usagePage: 0xff60, usage: 0x61, maxOutputReportSize: 32).isBatteryChannel)
    }

    func testParsesBatteryCommand() throws {
        XCTAssertEqual(try AK35iCommandParser.parse(["battery"]), .battery)
        XCTAssertThrowsError(try AK35iCommandParser.parse(["battery", "--apply"]))
    }
}
