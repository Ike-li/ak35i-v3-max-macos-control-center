import Foundation

/// Values of the driver's sleep combo (language IDs 142–145).
enum SleepTimeout: UInt8, CaseIterable {
    case never = 0
    case oneMinute
    case fiveMinutes
    case thirtyMinutes

    var cliName: String {
        switch self {
        case .never: return "never"
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .thirtyMinutes: return "30m"
        }
    }

    var displayName: String {
        switch self {
        case .never: return "不休眠"
        case .oneMinute: return "1 分钟"
        case .fiveMinutes: return "5 分钟"
        case .thirtyMinutes: return "30 分钟"
        }
    }
}

/// The keyboard has no read command for these, so every write sends all of
/// them; the defaults are the driver's first-run values (0x401b00).
struct SystemSettings: Equatable {
    static let responseLevels = Array(1...5)

    var disableAltTab = false
    var disableAltF4 = false
    var disableWin = false
    /// 0 or 1. The driver's buttons 使用单键 / 使用组合键 are inferred to write 0 / 1.
    var fnSwitch = 0
    var sleep = SleepTimeout.fiveMinutes
    var responseLevel = 2
}

/// System config sequence of DeviceDriver.exe 0x413ff0.
enum SystemSettingsProtocol {
    static func packets(for settings: SystemSettings) -> [FeaturePacket] {
        var preamble = LightingProtocol.command(0x17, followingPackets: 1)
        preamble[3] = 0x01

        var data = [UInt8](repeating: 0, count: ClockProtocol.reportLength)
        data[2] = 0x01
        data[3] = settings.disableAltTab ? 1 : 0
        data[4] = settings.disableAltF4 ? 1 : 0
        data[5] = settings.disableWin ? 1 : 0
        data[6] = UInt8(settings.fnSwitch)
        data[7] = settings.sleep.rawValue
        data[9] = UInt8(settings.responseLevel)
        data[63] = 0xaa
        data[64] = 0x55

        return [
            FeaturePacket(report: LightingProtocol.command(0x18), expectsAck: true),
            FeaturePacket(report: preamble, expectsAck: true),
            FeaturePacket(report: data, expectsAck: false),
            FeaturePacket(report: LightingProtocol.command(0x02), expectsAck: true),
        ]
    }
}
