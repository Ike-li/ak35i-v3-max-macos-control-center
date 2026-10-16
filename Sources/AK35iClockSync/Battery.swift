import Foundation

enum BatteryError: LocalizedError {
    case noReply
    case invalidReply([UInt8])
    case wired

    var errorDescription: String? {
        switch self {
        case .noReply:
            return "接收器没有转回键盘的应答：键盘可能没开机、没拨到 2.4G 档，或没和这个接收器配对。"
        case .invalidReply(let reply):
            return "键盘应答无法识别：" + reply.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        case .wired:
            return "有线 USB 下键盘不提供电量，请看键盘屏幕；改用 2.4G 接收器或蓝牙连接时可以读取。"
        }
    }
}

/// Battery query of DeviceDriver.exe 0x435ea0, which the driver only sends
/// through the 2.4G receiver: `20 01` in a 32-byte Output report whose last
/// byte is the sum of the others (0x4501c0). The keyboard echoes `20 01 00`
/// and puts the percentage shown on its screen in byte 3 (firmware 0x6B74).
/// Over wired USB the keyboard does not report its battery at all.
enum BatteryProtocol {
    static let reportLength = 32

    static let request = WirelessProtocol.packet(0x20, length: 0x01, data: [])

    /// The percentage, or nil for a reply the driver would not accept.
    static func level(from reply: [UInt8]) -> Int? {
        guard reply.count > 3, Array(reply[0...2]) == Array(request[0...2]), reply[3] != 0 else { return nil }
        return min(Int(reply[3]), 100)
    }
}
