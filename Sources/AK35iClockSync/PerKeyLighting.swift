import Foundation

struct KeyboardKey {
    let name: String
    let light: UInt8
    /// Rectangle in the driver's 800 × 300 layout image.
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(_ name: String, _ light: UInt8, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.name = name
        self.light = light
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Light indices and rectangles of the 104 keys, taken from the driver's
/// rgb-keyboard.xml. Names are shell-friendly replacements for its labels.
enum KeyboardLayout {
    static let keys: [KeyboardKey] = [
        KeyboardKey("Esc", 1, 35, 53, 24, 25),
        KeyboardKey("F1", 2, 100, 53, 24, 25),
        KeyboardKey("F2", 3, 132, 53, 24, 25),
        KeyboardKey("F3", 4, 165, 53, 24, 25),
        KeyboardKey("F4", 5, 198, 53, 24, 25),
        KeyboardKey("F5", 6, 247, 53, 24, 25),
        KeyboardKey("F6", 7, 280, 53, 24, 25),
        KeyboardKey("F7", 8, 312, 53, 24, 25),
        KeyboardKey("F8", 9, 345, 53, 24, 25),
        KeyboardKey("F9", 10, 393, 53, 24, 25),
        KeyboardKey("F10", 11, 426, 53, 24, 25),
        KeyboardKey("F11", 12, 459, 53, 24, 25),
        KeyboardKey("F12", 13, 492, 53, 24, 25),
        KeyboardKey("PrtSc", 112, 532, 53, 24, 25),
        KeyboardKey("ScrLk", 113, 565, 53, 24, 25),
        KeyboardKey("Pause", 115, 598, 53, 24, 25),
        KeyboardKey("Grave", 19, 35, 99, 24, 25),
        KeyboardKey("1", 20, 68, 99, 24, 25),
        KeyboardKey("2", 21, 100, 99, 24, 25),
        KeyboardKey("3", 22, 132, 99, 24, 25),
        KeyboardKey("4", 23, 165, 99, 24, 25),
        KeyboardKey("5", 24, 198, 99, 24, 25),
        KeyboardKey("6", 25, 231, 99, 24, 25),
        KeyboardKey("7", 26, 263, 99, 24, 25),
        KeyboardKey("8", 27, 296, 99, 24, 25),
        KeyboardKey("9", 28, 329, 99, 24, 25),
        KeyboardKey("0", 29, 361, 99, 24, 25),
        KeyboardKey("Minus", 30, 394, 99, 24, 25),
        KeyboardKey("Equal", 31, 426, 99, 24, 25),
        KeyboardKey("Backspace", 103, 458, 99, 58, 25),
        KeyboardKey("Insert", 116, 532, 99, 24, 25),
        KeyboardKey("Home", 117, 565, 99, 24, 25),
        KeyboardKey("PgUp", 118, 598, 99, 24, 25),
        KeyboardKey("NumLock", 32, 639, 99, 24, 25),
        KeyboardKey("NumSlash", 33, 672, 99, 24, 25),
        KeyboardKey("NumStar", 34, 705, 99, 24, 25),
        KeyboardKey("NumMinus", 122, 738, 99, 24, 25),
        KeyboardKey("Tab", 37, 35, 131, 40, 25),
        KeyboardKey("Q", 38, 84, 131, 24, 25),
        KeyboardKey("W", 39, 116, 131, 24, 25),
        KeyboardKey("E", 40, 149, 131, 24, 25),
        KeyboardKey("R", 41, 181, 131, 24, 25),
        KeyboardKey("T", 42, 214, 131, 24, 25),
        KeyboardKey("Y", 43, 246, 131, 24, 25),
        KeyboardKey("U", 44, 279, 131, 24, 25),
        KeyboardKey("I", 45, 312, 131, 24, 25),
        KeyboardKey("O", 46, 345, 131, 24, 25),
        KeyboardKey("P", 47, 378, 131, 24, 25),
        KeyboardKey("LBracket", 48, 410, 131, 24, 25),
        KeyboardKey("RBracket", 49, 442, 131, 24, 25),
        KeyboardKey("Backslash", 67, 474, 131, 42, 25),
        KeyboardKey("Delete", 119, 532, 131, 24, 25),
        KeyboardKey("End", 120, 565, 131, 24, 25),
        KeyboardKey("PgDn", 121, 598, 131, 24, 25),
        KeyboardKey("Num7", 50, 639, 131, 24, 25),
        KeyboardKey("Num8", 51, 672, 131, 24, 25),
        KeyboardKey("Num9", 52, 705, 131, 24, 25),
        KeyboardKey("NumPlus", 123, 738, 131, 24, 59),
        KeyboardKey("CapsLock", 55, 35, 164, 49, 25),
        KeyboardKey("A", 56, 92, 164, 24, 25),
        KeyboardKey("S", 57, 125, 164, 24, 25),
        KeyboardKey("D", 58, 158, 164, 24, 25),
        KeyboardKey("F", 59, 190, 164, 24, 25),
        KeyboardKey("G", 60, 223, 164, 24, 25),
        KeyboardKey("H", 61, 256, 164, 24, 25),
        KeyboardKey("J", 62, 288, 164, 24, 25),
        KeyboardKey("K", 63, 320, 164, 24, 25),
        KeyboardKey("L", 64, 353, 164, 24, 25),
        KeyboardKey("Semicolon", 65, 385, 164, 24, 25),
        KeyboardKey("Quote", 66, 418, 164, 24, 25),
        KeyboardKey("Enter", 85, 451, 164, 65, 25),
        KeyboardKey("Num4", 68, 639, 164, 24, 25),
        KeyboardKey("Num5", 69, 672, 164, 24, 25),
        KeyboardKey("Num6", 70, 705, 164, 24, 25),
        KeyboardKey("LShift", 73, 35, 196, 65, 25),
        KeyboardKey("Z", 74, 108, 196, 24, 25),
        KeyboardKey("X", 75, 141, 196, 24, 25),
        KeyboardKey("C", 76, 173, 196, 24, 25),
        KeyboardKey("V", 77, 206, 196, 24, 25),
        KeyboardKey("B", 78, 238, 196, 24, 25),
        KeyboardKey("N", 79, 271, 196, 24, 25),
        KeyboardKey("M", 80, 304, 196, 24, 25),
        KeyboardKey("Comma", 81, 337, 196, 24, 25),
        KeyboardKey("Period", 82, 369, 196, 24, 25),
        KeyboardKey("Slash", 83, 401, 196, 24, 25),
        KeyboardKey("RShift", 84, 434, 196, 82, 25),
        KeyboardKey("Up", 101, 565, 196, 24, 25),
        KeyboardKey("Num1", 86, 639, 196, 24, 25),
        KeyboardKey("Num2", 87, 672, 196, 24, 25),
        KeyboardKey("Num3", 88, 705, 196, 24, 25),
        KeyboardKey("NumEnter", 106, 738, 196, 24, 59),
        KeyboardKey("LCtrl", 91, 35, 230, 33, 25),
        KeyboardKey("LWin", 92, 76, 230, 33, 25),
        KeyboardKey("LAlt", 93, 117, 230, 33, 25),
        KeyboardKey("Space", 94, 159, 230, 191, 25),
        KeyboardKey("RAlt", 95, 360, 230, 33, 25),
        KeyboardKey("Fn", 96, 401, 230, 33, 25),
        KeyboardKey("Menu", 97, 442, 230, 33, 25),
        KeyboardKey("RCtrl", 98, 482, 230, 33, 25),
        KeyboardKey("Left", 99, 532, 230, 24, 25),
        KeyboardKey("Down", 100, 565, 230, 24, 25),
        KeyboardKey("Right", 102, 598, 230, 24, 25),
        KeyboardKey("Num0", 104, 639, 230, 57, 25),
        KeyboardKey("NumPeriod", 105, 705, 230, 24, 25),
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

/// Per-key editor form state. The keyboard is written with exactly these
/// colours, so the request starts from black rather than the stored scheme.
struct PerKeyEditorState: Equatable {
    var colors = Dictionary(uniqueKeysWithValues: KeyboardLayout.keys.map { ($0.light, RGBColor(red: 0, green: 0, blue: 0)) })
    var selection: Set<UInt8> = []

    mutating func toggle(_ light: UInt8) {
        if selection.remove(light) == nil { selection.insert(light) }
    }

    mutating func paintSelection(_ color: RGBColor) {
        for light in selection { colors[light] = color }
    }

    mutating func fill(_ color: RGBColor) {
        for light in colors.keys { colors[light] = color }
    }

    func request(brightness: Int) -> PerKeyColorRequest {
        PerKeyColorRequest(brightness: brightness, clear: true, keys: colors)
    }
}
