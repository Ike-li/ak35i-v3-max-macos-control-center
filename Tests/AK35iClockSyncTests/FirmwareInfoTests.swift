import XCTest
@testable import AK35iClockSync

final class FirmwareInfoTests: XCTestCase {
    /// The block at firmware 0x8F80 that `02 00` returns over 2.4G: constant,
    /// VID, PID and the version, all little endian (dantje/ajazz-ak35i-v3-max).
    func testParsesTheInformationBlock() {
        let keyboard = FirmwareInfo(block: [0x40, 0x30, 0x00, 0x00, 0x45, 0x0c, 0x09, 0x80, 0x30, 0x01, 0xff, 0xff])
        XCTAssertEqual(keyboard, FirmwareInfo(vendorID: 0x0c45, productID: 0x8009, version: 0x0130))
        XCTAssertEqual(keyboard?.versionText, "V1.30")

        let image = FirmwareInfo(block: [0x40, 0x30, 0x00, 0x00, 0xac, 0x05, 0x4f, 0x02, 0x17, 0x01, 0xff, 0xff])
        XCTAssertEqual(image?.versionText, "V1.17")
        XCTAssertEqual(image?.productID, 0x024f)
        XCTAssertEqual(FirmwareInfo.versionText(0x0127), "V1.27")

        XCTAssertNil(FirmwareInfo(block: [0x40, 0x30, 0x00]))
        XCTAssertNil(FirmwareInfo(block: Array(repeating: 0xff, count: 12)), "erased flash")
    }

    /// The probe answer echoes `02 00 00` and carries the block from byte 3.
    func testReadsTheBlockFromTheProbeAnswer() {
        let reply: [UInt8] = [0x02, 0x00, 0x00, 0x40, 0x30, 0x00, 0x00, 0x45, 0x0c, 0x09, 0x80, 0x30, 0x01, 0xff, 0xff]
            + Array(repeating: 0, count: 16) + [0x7b]
        XCTAssertEqual(FirmwareInfo(probeReply: reply)?.versionText, "V1.30")
        XCTAssertNil(FirmwareInfo(probeReply: [0x20, 0x01, 0x00] + Array(repeating: 0, count: 29)))
    }
}
