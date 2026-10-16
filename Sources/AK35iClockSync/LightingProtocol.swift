import Foundation

/// One 65-byte Feature report (leading report ID 0, as in ClockProtocol) and
/// whether the Windows driver reads back an acknowledgement after sending it.
struct FeaturePacket: Equatable {
    let report: [UInt8]
    let expectsAck: Bool
}

struct RGBColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

enum LightingColor: Equatable {
    case colorful
    case solid(RGBColor)
}

/// Mode numbers and names come from the driver's default `t_light_data` rows
/// (0x42b6b0) and language IDs 521–540.
enum LightingMode: UInt8, CaseIterable {
    case off = 0
    case staticColor
    case singleOn
    case singleOff
    case starry
    case snowfall
    case blossom
    case breathing
    case spectrumCycle
    case fountain
    case crossColor
    case wave
    case winding
    case trigger
    case doubleHit
    case ripple
    case stream
    case ridges
    case drizzle
    case shuttle

    var displayName: String {
        switch self {
        case .off: return "关闭背光"
        case .staticColor: return "静态恒亮"
        case .singleOn: return "单点亮"
        case .singleOff: return "单熄灭"
        case .starry: return "繁星点点"
        case .snowfall: return "漫天飞雪"
        case .blossom: return "百花争艳"
        case .breathing: return "动态呼吸"
        case .spectrumCycle: return "光谱循环"
        case .fountain: return "彩泉涌动"
        case .crossColor: return "多彩纵横"
        case .wave: return "随波逐流"
        case .winding: return "峰回路转"
        case .trigger: return "一触即发"
        case .doubleHit: return "一石二鸟"
        case .ripple: return "涟漪扩散"
        case .stream: return "川流不息"
        case .ridges: return "重峦叠嶂"
        case .drizzle: return "斜风细雨"
        case .shuttle: return "来回穿梭"
        }
    }

    /// `config_func` of the default row: which controls the driver shows.
    private var controls: UInt8 {
        switch self {
        case .off: return 0x00
        case .staticColor: return 0x31
        case .blossom, .spectrumCycle: return 0x03
        case .crossColor: return 0x3b
        case .wave, .winding, .stream, .drizzle: return 0x37
        case .singleOn, .singleOff, .starry, .snowfall, .breathing, .fountain,
             .trigger, .doubleHit, .ripple, .ridges, .shuttle:
            return 0x33
        }
    }

    var supportsBrightness: Bool { controls & 0x01 != 0 }
    var supportsSpeed: Bool { controls & 0x02 != 0 }
    var supportsColor: Bool { controls & 0x20 != 0 }

    /// Values handler 0x42c930 can store; nil when the mode shows no direction buttons.
    var allowedDirections: [Int]? {
        if controls & 0x04 != 0 { return [0, 1] }
        if controls & 0x08 != 0 { return [0, 2, 3] }
        return nil
    }
}

enum LightingParameter: String, Equatable {
    case brightness
    case speed
    case direction
    case color

    var displayName: String {
        switch self {
        case .brightness: return "亮度"
        case .speed: return "速度"
        case .direction: return "方向"
        case .color: return "颜色"
        }
    }
}

enum LightingEffectError: LocalizedError, Equatable {
    case unsupported(LightingParameter, mode: LightingMode)
    case outOfRange(LightingParameter, value: Int, allowed: [Int])

    var errorDescription: String? {
        switch self {
        case .unsupported(let parameter, let mode):
            return "灯效「\(mode.displayName)」不支持设置\(parameter.displayName)。"
        case .outOfRange(let parameter, let value, let allowed):
            let values = allowed.map(String.init).joined(separator: "、")
            return "\(parameter.displayName) \(value) 超出驱动可发送的取值（\(values)）。"
        }
    }
}

struct LightingEffect: Equatable {
    static let levels = Array(0...5)
    static let defaultBrightness = 5
    static let defaultSpeed = 3
    static let defaultColor = RGBColor(red: 0xff, green: 0x00, blue: 0x00)

    let mode: LightingMode
    let brightness: Int
    let speed: Int
    let direction: Int
    let color: LightingColor

    init(
        mode: LightingMode,
        brightness: Int? = nil,
        speed: Int? = nil,
        direction: Int? = nil,
        color: LightingColor? = nil
    ) throws {
        if let brightness {
            guard mode.supportsBrightness else { throw LightingEffectError.unsupported(.brightness, mode: mode) }
            guard Self.levels.contains(brightness) else {
                throw LightingEffectError.outOfRange(.brightness, value: brightness, allowed: Self.levels)
            }
        }
        if let speed {
            guard mode.supportsSpeed else { throw LightingEffectError.unsupported(.speed, mode: mode) }
            guard Self.levels.contains(speed) else {
                throw LightingEffectError.outOfRange(.speed, value: speed, allowed: Self.levels)
            }
        }
        if let direction {
            guard let allowed = mode.allowedDirections else {
                throw LightingEffectError.unsupported(.direction, mode: mode)
            }
            guard allowed.contains(direction) else {
                throw LightingEffectError.outOfRange(.direction, value: direction, allowed: allowed)
            }
        }
        if color != nil, !mode.supportsColor {
            throw LightingEffectError.unsupported(.color, mode: mode)
        }

        self.mode = mode
        self.brightness = brightness ?? Self.defaultBrightness
        self.speed = speed ?? Self.defaultSpeed
        self.direction = direction ?? 0
        self.color = color ?? .colorful
    }
}

/// Basic lighting sequence of DeviceDriver.exe 0x42b400.
enum LightingProtocol {
    static func packets(for effect: LightingEffect) -> [FeaturePacket] {
        var data = blankReport()
        data[1] = effect.mode.rawValue
        if effect.mode != .off {
            let rgb: RGBColor
            switch effect.color {
            case .colorful: rgb = LightingEffect.defaultColor
            case .solid(let color): rgb = color
            }
            data[2] = rgb.red
            data[3] = rgb.green
            data[4] = rgb.blue
            data[9] = effect.color == .colorful ? 1 : 0
            data[10] = UInt8(effect.brightness)
            data[11] = UInt8(effect.speed)
            data[12] = UInt8(effect.direction)
        }
        data[15] = 0xaa
        data[16] = 0x55
        return modeSession(data: data)
    }

    /// Per-key custom mode (0x44c4e0): mode 0x80 carrying only the brightness.
    static func customModePackets(brightness: Int) -> [FeaturePacket] {
        var data = blankReport()
        data[1] = 0x80
        data[10] = UInt8(brightness)
        data[15] = 0xaa
        data[16] = 0x55
        return modeSession(data: data)
    }

    private static func modeSession(data: [UInt8]) -> [FeaturePacket] {
        [
            FeaturePacket(report: command(0x18), expectsAck: true),
            FeaturePacket(report: command(0x13, followingPackets: 1), expectsAck: true),
            FeaturePacket(report: data, expectsAck: false),
            FeaturePacket(report: command(0x02), expectsAck: true),
            FeaturePacket(report: command(0xf0), expectsAck: false),
        ]
    }

    static func command(_ code: UInt8, followingPackets: UInt8 = 0) -> [UInt8] {
        var report = blankReport()
        report[1] = 0x04
        report[2] = code
        report[9] = followingPackets
        return report
    }

    private static func blankReport() -> [UInt8] {
        Array(repeating: 0, count: ClockProtocol.reportLength)
    }
}
