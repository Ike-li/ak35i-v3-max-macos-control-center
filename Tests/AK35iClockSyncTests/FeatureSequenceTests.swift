import XCTest
@testable import AK35iClockSync

final class FeatureSequenceTests: XCTestCase {
    private func report(_ prefix: [UInt8]) -> [UInt8] {
        [0] + prefix + Array(repeating: 0, count: 64 - prefix.count)
    }

    private func response(_ prefix: [UInt8]) -> [UInt8] {
        prefix + Array(repeating: 0, count: 64 - prefix.count)
    }

    /// Responses read back from the keyboard on 2026-10-16.
    func testAcknowledgementRequiresEchoedCommandAndStatusByte() {
        XCTAssertTrue(FeatureAck.isAcknowledged(report: report([0x04, 0x18]), response: response([0x04, 0x18, 0x00, 0x01])))
        XCTAssertTrue(FeatureAck.isAcknowledged(report: report([0x04, 0x02]), response: response([0x04, 0x02, 0x00, 0x01, 0x07, 0x02])))
        XCTAssertFalse(FeatureAck.isAcknowledged(report: report([0x04, 0x13]), response: response([0x04, 0x18, 0x00, 0x01])))
        XCTAssertFalse(FeatureAck.isAcknowledged(report: report([0x00, 0x01, 0x5a, 0x1a]), response: response([0x00, 0x01, 0x5a, 0x1a])))
        XCTAssertFalse(FeatureAck.isAcknowledged(report: report([0x04, 0x18]), response: response([])))
        XCTAssertFalse(FeatureAck.isAcknowledged(report: report([0x04, 0x18]), response: [0x04, 0x18, 0x00]))
    }

    func testFollowsDriverTimingAndReadsOnlyAfterAcknowledgedPackets() throws {
        let device = FakeFeatureDevice(acknowledging: true)
        var log: [String] = []
        device.onEvent = { log.append($0) }

        let result = try FeatureSequenceWriter.send(
            LightingProtocol.packets(for: try LightingEffect(mode: .wave)),
            to: device,
            sleep: { log.append("sleep \($0)") }
        )

        XCTAssertEqual(result.unacknowledgedPackets, [])
        XCTAssertEqual(log, [
            "sleep 0.035", "write 1", "sleep 0.035", "read",
            "sleep 0.035", "write 2", "sleep 0.035", "read",
            "sleep 0.035", "write 3",
            "sleep 0.035", "write 4", "sleep 0.035", "read",
            "sleep 0.035", "write 5",
        ])
    }

    func testStopsBeforeLightingDataWhenStartIsNotAcknowledged() throws {
        let device = FakeFeatureDevice(acknowledging: false)

        XCTAssertThrowsError(try FeatureSequenceWriter.send(
            LightingProtocol.packets(for: try LightingEffect(mode: .wave)),
            to: device,
            sleep: { _ in }
        )) { error in
            XCTAssertEqual(error as? FeatureSequenceError, .startNotAcknowledged)
        }
        XCTAssertEqual(device.writtenReports.count, 1)
    }

    func testFinishesTheSessionAndReportsLaterMissingAcknowledgements() throws {
        let device = FakeFeatureDevice(acknowledging: true)
        device.unacknowledgedCommands = [0x02]

        let result = try FeatureSequenceWriter.send(
            LightingProtocol.packets(for: try LightingEffect(mode: .wave)),
            to: device,
            sleep: { _ in }
        )

        XCTAssertEqual(device.writtenReports.count, 5)
        XCTAssertEqual(result.unacknowledgedPackets, [4])
    }
}

/// Stands in for the IOKit HID interface: echoes the last command with the
/// status byte the keyboard returned during the 2026-10-16 trial.
private final class FakeFeatureDevice: FeatureReportDevice {
    var onEvent: (String) -> Void = { _ in }
    var unacknowledgedCommands: Set<UInt8> = []
    private(set) var writtenReports: [[UInt8]] = []
    private let acknowledging: Bool

    init(acknowledging: Bool) {
        self.acknowledging = acknowledging
    }

    func writeFeature(_ report: [UInt8], packetIndex: Int) throws {
        writtenReports.append(report)
        onEvent("write \(packetIndex)")
    }

    func readFeature() throws -> [UInt8] {
        onEvent("read")
        var response = Array(writtenReports.last!.dropFirst())
        let ack = acknowledging && !unacknowledgedCommands.contains(response[1])
        response[3] = ack ? 0x01 : 0x00
        return response
    }
}
