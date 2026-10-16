import Foundation

enum WirelessError: LocalizedError, Equatable {
    case keyboardOffline
    case noReply(packet: Int, of: Int)
    case noReadback
    case musicOnly

    var errorDescription: String? {
        switch self {
        case .keyboardOffline:
            return "2.4G 接收器已连接，但键盘没有应答：请确认键盘已开机、拨到 2.4G 档，并和这个接收器配对。"
        case .noReply(let packet, let total):
            return "第 \(packet)/\(total) 包没有收到键盘应答，已停止发送，之前的包已写入键盘。"
        case .noReadback:
            return "2.4G 下键盘不提供读回，读不到已保存的单键颜色；请用数据线连接后读取。"
        case .musicOnly:
            return "2.4G 下键盘只支持音乐律动（柱状图），波浪、呼吸、繁星和纯色需要用数据线连接。"
        }
    }
}

/// 2.4G packets of DeviceDriver.exe 0x4501c0: 32 bytes without a report ID,
/// p0 command, p1 length, p2 sequence, p3–p30 data and p31 the sum of p0–p30.
/// The keyboard handles them at firmware 0x67C8, one at a time, without the
/// wired `04 18` / `04 02` session, and answers by echoing p0–p2.
enum WirelessProtocol {
    static let packetLength = 32
    static let dataLength = 28

    /// `02 00`, which the driver sends to see whether the keyboard is online
    /// (0x450360); the answer carries the firmware's information block.
    static let probe = packet(0x02, length: 0x00, data: [])

    static func packet(_ command: UInt8, length: UInt8, sequence: UInt8 = 0, data: [UInt8]) -> [UInt8] {
        precondition(data.count <= dataLength, "a 2.4G packet carries at most 28 data bytes")
        var packet = [command, length, sequence] + data
        packet += Array(repeating: 0, count: packetLength - 1 - packet.count)
        packet.append(packet.reduce(0, &+))
        return packet
    }

    /// Single-packet settings (clock, lighting, system): the first 14 bytes of
    /// the wired data frame followed by `AA 55`, as 0x423bf0, 0x42b5a0 and
    /// 0x414260 build them.
    static func settings(_ command: UInt8, frame: [UInt8]) -> [UInt8] {
        packet(command, length: 0x10, data: Array(frame.prefix(14)) + [0xaa, 0x55])
    }

    /// A block in 28-byte packets numbered from 0, the last carrying what is
    /// left, as the driver streams keymaps (0x418e30) and colours (0x44ca60).
    /// The firmware writes each to base + 28 × sequence with no upper bound,
    /// so callers keep blocks inside their flash page.
    static func stream(_ command: UInt8, data: [UInt8]) -> [[UInt8]] {
        stride(from: 0, to: data.count, by: dataLength).map { start in
            let chunk = Array(data[start..<min(start + dataLength, data.count)])
            return packet(command, length: UInt8(chunk.count), sequence: UInt8(start / dataLength), data: chunk)
        }
    }
}

/// Anything that can send one 2.4G packet and return the keyboard's echo.
protocol WirelessExchanging {
    func exchange(_ report: [UInt8], timeout: TimeInterval) throws -> [UInt8]?
}

enum WirelessSender {
    /// The driver's pause between chunks.
    static let packetDelay: TimeInterval = 0.002
    /// Packets that write flash are answered only after the write.
    static let replyTimeout: TimeInterval = 1.0

    /// Checks that the keyboard answers, then sends every packet and waits for
    /// its echo. Stops at the first packet without one: the firmware writes
    /// streamed data without bounds checks, so nothing is sent blindly.
    static func send(_ packets: [[UInt8]], over receiver: WirelessExchanging, progress: (Int) -> Void = { _ in }) throws {
        guard try receiver.exchange(WirelessProtocol.probe, timeout: replyTimeout) != nil else {
            throw WirelessError.keyboardOffline
        }
        for (index, packet) in packets.enumerated() {
            guard try receiver.exchange(packet, timeout: replyTimeout) != nil else {
                throw WirelessError.noReply(packet: index + 1, of: packets.count)
            }
            progress(index + 1)
            Thread.sleep(forTimeInterval: packetDelay)
        }
    }
}

extension AK35iReceiverTransport: WirelessExchanging {}
