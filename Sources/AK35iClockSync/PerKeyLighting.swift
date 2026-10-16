import Foundation

/// Light indices of the 104 keys, taken from the driver's rgb-keyboard.xml.
/// Names are shell-friendly replacements for the driver's labels.
enum KeyboardLayout {
    static let keys: [(name: String, light: UInt8)] = [
        ("Esc", 1), ("F1", 2), ("F2", 3), ("F3", 4), ("F4", 5), ("F5", 6), ("F6", 7), ("F7", 8),
        ("F8", 9), ("F9", 10), ("F10", 11), ("F11", 12), ("F12", 13), ("PrtSc", 112), ("ScrLk", 113), ("Pause", 115),

        ("Grave", 19), ("1", 20), ("2", 21), ("3", 22), ("4", 23), ("5", 24), ("6", 25), ("7", 26),
        ("8", 27), ("9", 28), ("0", 29), ("Minus", 30), ("Equal", 31), ("Backspace", 103),
        ("Insert", 116), ("Home", 117), ("PgUp", 118),
        ("NumLock", 32), ("NumSlash", 33), ("NumStar", 34), ("NumMinus", 122),

        ("Tab", 37), ("Q", 38), ("W", 39), ("E", 40), ("R", 41), ("T", 42), ("Y", 43), ("U", 44),
        ("I", 45), ("O", 46), ("P", 47), ("LBracket", 48), ("RBracket", 49), ("Backslash", 67),
        ("Delete", 119), ("End", 120), ("PgDn", 121),
        ("Num7", 50), ("Num8", 51), ("Num9", 52), ("NumPlus", 123),

        ("CapsLock", 55), ("A", 56), ("S", 57), ("D", 58), ("F", 59), ("G", 60), ("H", 61), ("J", 62),
        ("K", 63), ("L", 64), ("Semicolon", 65), ("Quote", 66), ("Enter", 85),
        ("Num4", 68), ("Num5", 69), ("Num6", 70),

        ("LShift", 73), ("Z", 74), ("X", 75), ("C", 76), ("V", 77), ("B", 78), ("N", 79), ("M", 80),
        ("Comma", 81), ("Period", 82), ("Slash", 83), ("RShift", 84), ("Up", 101),
        ("Num1", 86), ("Num2", 87), ("Num3", 88), ("NumEnter", 106),

        ("LCtrl", 91), ("LWin", 92), ("LAlt", 93), ("Space", 94), ("RAlt", 95), ("Fn", 96), ("Menu", 97),
        ("RCtrl", 98), ("Left", 99), ("Down", 100), ("Right", 102), ("Num0", 104), ("NumPeriod", 105),
    ]

    static func light(named name: String) -> UInt8? {
        keys.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.light
    }
}

/// Custom per-key colours for an `rgb_keyboard="1"` layout: writer 0x44c5f0
/// (04 23) and reader 0x42b1e0 (04 F5), 4 bytes per light in 9 × 64 bytes.
enum PerKeyProtocol {
    static let chunkCount = 9
    static let blockLength = chunkCount * 64

    static let readRequest = LightingProtocol.command(0xf5, followingPackets: UInt8(chunkCount))

    /// Lights missing from `colors` are written black, as the driver does for
    /// keys outside the selected scheme.
    static func writePackets(colors: [UInt8: RGBColor]) -> [FeaturePacket] {
        var block = [UInt8](repeating: 0, count: blockLength)
        for key in KeyboardLayout.keys {
            let slot = 4 * Int(key.light)
            let color = colors[key.light] ?? RGBColor(red: 0, green: 0, blue: 0)
            block[slot] = key.light
            block[slot + 1] = color.red
            block[slot + 2] = color.green
            block[slot + 3] = color.blue
        }
        block[blockLength - 2] = 0xaa
        block[blockLength - 1] = 0x55

        let chunks = (0..<chunkCount).map { index in
            FeaturePacket(report: [0] + block[index * 64..<(index + 1) * 64], expectsAck: false)
        }
        return [
            FeaturePacket(report: LightingProtocol.command(0x18), expectsAck: true),
            FeaturePacket(report: LightingProtocol.command(0x23, followingPackets: UInt8(chunkCount)), expectsAck: true),
        ] + chunks + [
            FeaturePacket(report: LightingProtocol.command(0x02), expectsAck: true),
            FeaturePacket(report: LightingProtocol.command(0xf0), expectsAck: true),
        ]
    }

    static func colors(fromBlock block: [UInt8]) -> [UInt8: RGBColor]? {
        guard block.count >= blockLength else { return nil }
        var colors: [UInt8: RGBColor] = [:]
        for key in KeyboardLayout.keys {
            let slot = 4 * Int(key.light)
            colors[key.light] = RGBColor(red: block[slot + 1], green: block[slot + 2], blue: block[slot + 3])
        }
        return colors
    }
}

enum PerKeyVerification {
    /// The keyboard reads back about 6 bits per channel (FF → FC), so only
    /// lit-versus-dark per channel is compared; values below 8 are too dim to judge.
    static func mismatchedLights(expected: [UInt8: RGBColor], readBack: [UInt8: RGBColor]) -> [UInt8] {
        func agrees(_ want: UInt8, _ got: UInt8) -> Bool {
            if want == 0 { return got == 0 }
            if want < 8 { return true }
            return got > 0
        }
        return expected.keys.sorted().filter { light in
            let want = expected[light]!
            guard let got = readBack[light] else { return true }
            return !(agrees(want.red, got.red) && agrees(want.green, got.green) && agrees(want.blue, got.blue))
        }
    }
}

struct PerKeyColorRequest: Equatable {
    var brightness = LightingEffect.defaultBrightness
    /// Start from black instead of the colours already stored on the keyboard.
    var clear = false
    var all: RGBColor?
    var keys: [UInt8: RGBColor] = [:]

    func resolve(stored: [UInt8: RGBColor]) -> [UInt8: RGBColor] {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        var colors: [UInt8: RGBColor] = [:]
        for key in KeyboardLayout.keys {
            colors[key.light] = keys[key.light] ?? all ?? (clear ? black : stored[key.light] ?? black)
        }
        return colors
    }
}

enum PerKeyLightingError: LocalizedError, Equatable {
    case storedColorsUnstable
    case verificationFailed([String])

    var errorDescription: String? {
        switch self {
        case .storedColorsUnstable:
            return "两次读回的颜色不一致，键盘可能没有进入自定义单键模式；已停止，未写入颜色。"
        case .verificationFailed(let names):
            return "写入后读回核对不一致：\(names.joined(separator: "、"))。可用 Fn+\\| 切回其他灯效。"
        }
    }
}
