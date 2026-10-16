import Foundation

protocol FeatureReportDevice: AnyObject {
    func writeFeature(_ report: [UInt8], packetIndex: Int) throws
    func readFeature() throws -> [UInt8]
}

enum FeatureAck {
    /// The keyboard answers a `04 xx` command by echoing it with byte 3 set
    /// to 0x01. Data packets are echoed verbatim and never carry this ACK.
    static func isAcknowledged(report: [UInt8], response: [UInt8]) -> Bool {
        let payload = HIDFeatureReport.macOSPayload(from: report)
        return response.count >= 4
            && response[0] == payload[0]
            && response[1] == payload[1]
            && response[3] == 0x01
    }
}

struct FeatureSequenceResult: Equatable {
    /// 1-based indices of packets that expected an ACK but did not get one.
    let unacknowledgedPackets: [Int]
}

enum FeatureSequenceError: LocalizedError, Equatable {
    case startNotAcknowledged
    case packetsNotAcknowledged([Int])
    case readNotAcknowledged
    case shortRead(chunk: Int)

    var errorDescription: String? {
        switch self {
        case .startNotAcknowledged:
            return "键盘没有确认会话开始命令，已停止，未发送任何设置数据。"
        case .readNotAcknowledged:
            return "键盘没有确认读取命令。"
        case .shortRead(let chunk):
            return "第 \(chunk) 块读回数据不完整。"
        case .packetsNotAcknowledged(let indices):
            let list = indices.map(String.init).joined(separator: "、")
            return "第 \(list) 个命令未收到键盘确认；会话已按驱动顺序结束。请查看灯效，必要时用 Fn+\\| 切换恢复。"
        }
    }
}

enum FeatureSequenceWriter {
    /// `cmd_delaytime` in the driver's rgb-keyboard.xml.
    static let packetDelay: TimeInterval = 0.035

    /// Mirrors DeviceDriver.exe 0x44faa0. Unlike the driver, it refuses to
    /// continue when the opening packet is not acknowledged; later misses are
    /// reported after the session is closed the same way the driver closes it.
    static func send(
        _ packets: [FeaturePacket],
        to device: FeatureReportDevice,
        sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) throws -> FeatureSequenceResult {
        var unacknowledged: [Int] = []
        for (index, packet) in packets.enumerated() {
            sleep(packetDelay)
            try device.writeFeature(packet.report, packetIndex: index + 1)
            guard packet.expectsAck else { continue }

            sleep(packetDelay)
            let response = (try? device.readFeature()) ?? []
            if FeatureAck.isAcknowledged(report: packet.report, response: response) { continue }
            if index == 0 { throw FeatureSequenceError.startNotAcknowledged }
            unacknowledged.append(index + 1)
        }
        return FeatureSequenceResult(unacknowledgedPackets: unacknowledged)
    }
}

enum FeatureBlockReader {
    /// Mirrors DeviceDriver.exe 0x44ff70 followed by the `04 02` that 0x42b1e0
    /// always sends after a read: request, ACK, then one 64-byte chunk per read.
    static func read(
        request: [UInt8],
        chunks: Int,
        from device: FeatureReportDevice,
        sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) throws -> [UInt8] {
        sleep(0.010)
        try device.writeFeature(request, packetIndex: 1)
        sleep(0.005)
        let ack = (try? device.readFeature()) ?? []
        guard FeatureAck.isAcknowledged(report: request, response: ack) else {
            throw FeatureSequenceError.readNotAcknowledged
        }

        var block: [UInt8] = []
        for chunk in 1...chunks {
            sleep(0.003)
            let bytes = (try? device.readFeature()) ?? []
            guard bytes.count == 64 else { throw FeatureSequenceError.shortRead(chunk: chunk) }
            block += bytes
        }

        let commit = LightingProtocol.command(0x02)
        sleep(FeatureSequenceWriter.packetDelay)
        try device.writeFeature(commit, packetIndex: 2)
        sleep(FeatureSequenceWriter.packetDelay)
        guard FeatureAck.isAcknowledged(report: commit, response: (try? device.readFeature()) ?? []) else {
            throw FeatureSequenceError.readNotAcknowledged
        }
        return block
    }
}
