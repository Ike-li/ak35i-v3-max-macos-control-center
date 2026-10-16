import Foundation

struct KeyboardKey {
    let name: String
    let light: UInt8
    /// HID keyboard usage from the layout's `code` attribute; 0xAF for Fn is
    /// the driver's own value, not a standard usage.
    let usage: UInt8
    /// Rectangle in the driver's 800 × 300 layout image.
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(_ name: String, _ light: UInt8, _ usage: UInt8, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.name = name
        self.light = light
        self.usage = usage
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Light indices, HID usages and rectangles of the 104 keys, taken from the driver's
/// rgb-keyboard.xml. Names are shell-friendly replacements for its labels.
enum KeyboardLayout {
    static let keys: [KeyboardKey] = [
        KeyboardKey("Esc", 1, 0x29, 35, 53, 24, 25),
        KeyboardKey("F1", 2, 0x3A, 100, 53, 24, 25),
        KeyboardKey("F2", 3, 0x3B, 132, 53, 24, 25),
        KeyboardKey("F3", 4, 0x3C, 165, 53, 24, 25),
        KeyboardKey("F4", 5, 0x3D, 198, 53, 24, 25),
        KeyboardKey("F5", 6, 0x3E, 247, 53, 24, 25),
        KeyboardKey("F6", 7, 0x3F, 280, 53, 24, 25),
        KeyboardKey("F7", 8, 0x40, 312, 53, 24, 25),
        KeyboardKey("F8", 9, 0x41, 345, 53, 24, 25),
        KeyboardKey("F9", 10, 0x42, 393, 53, 24, 25),
        KeyboardKey("F10", 11, 0x43, 426, 53, 24, 25),
        KeyboardKey("F11", 12, 0x44, 459, 53, 24, 25),
        KeyboardKey("F12", 13, 0x45, 492, 53, 24, 25),
        KeyboardKey("PrtSc", 112, 0x46, 532, 53, 24, 25),
        KeyboardKey("ScrLk", 113, 0x47, 565, 53, 24, 25),
        KeyboardKey("Pause", 115, 0x48, 598, 53, 24, 25),
        KeyboardKey("Grave", 19, 0x35, 35, 99, 24, 25),
        KeyboardKey("1", 20, 0x1E, 68, 99, 24, 25),
        KeyboardKey("2", 21, 0x1F, 100, 99, 24, 25),
        KeyboardKey("3", 22, 0x20, 132, 99, 24, 25),
        KeyboardKey("4", 23, 0x21, 165, 99, 24, 25),
        KeyboardKey("5", 24, 0x22, 198, 99, 24, 25),
        KeyboardKey("6", 25, 0x23, 231, 99, 24, 25),
        KeyboardKey("7", 26, 0x24, 263, 99, 24, 25),
        KeyboardKey("8", 27, 0x25, 296, 99, 24, 25),
        KeyboardKey("9", 28, 0x26, 329, 99, 24, 25),
        KeyboardKey("0", 29, 0x27, 361, 99, 24, 25),
        KeyboardKey("Minus", 30, 0x2D, 394, 99, 24, 25),
        KeyboardKey("Equal", 31, 0x2E, 426, 99, 24, 25),
        KeyboardKey("Backspace", 103, 0x2A, 458, 99, 58, 25),
        KeyboardKey("Insert", 116, 0x49, 532, 99, 24, 25),
        KeyboardKey("Home", 117, 0x4A, 565, 99, 24, 25),
        KeyboardKey("PgUp", 118, 0x4B, 598, 99, 24, 25),
        KeyboardKey("NumLock", 32, 0x53, 639, 99, 24, 25),
        KeyboardKey("NumSlash", 33, 0x54, 672, 99, 24, 25),
        KeyboardKey("NumStar", 34, 0x55, 705, 99, 24, 25),
        KeyboardKey("NumMinus", 122, 0x56, 738, 99, 24, 25),
        KeyboardKey("Tab", 37, 0x2B, 35, 131, 40, 25),
        KeyboardKey("Q", 38, 0x14, 84, 131, 24, 25),
        KeyboardKey("W", 39, 0x1A, 116, 131, 24, 25),
        KeyboardKey("E", 40, 0x08, 149, 131, 24, 25),
        KeyboardKey("R", 41, 0x15, 181, 131, 24, 25),
        KeyboardKey("T", 42, 0x17, 214, 131, 24, 25),
        KeyboardKey("Y", 43, 0x1C, 246, 131, 24, 25),
        KeyboardKey("U", 44, 0x18, 279, 131, 24, 25),
        KeyboardKey("I", 45, 0x0C, 312, 131, 24, 25),
        KeyboardKey("O", 46, 0x12, 345, 131, 24, 25),
        KeyboardKey("P", 47, 0x13, 378, 131, 24, 25),
        KeyboardKey("LBracket", 48, 0x2F, 410, 131, 24, 25),
        KeyboardKey("RBracket", 49, 0x30, 442, 131, 24, 25),
        KeyboardKey("Backslash", 67, 0x31, 474, 131, 42, 25),
        KeyboardKey("Delete", 119, 0x4C, 532, 131, 24, 25),
        KeyboardKey("End", 120, 0x4D, 565, 131, 24, 25),
        KeyboardKey("PgDn", 121, 0x4E, 598, 131, 24, 25),
        KeyboardKey("Num7", 50, 0x5F, 639, 131, 24, 25),
        KeyboardKey("Num8", 51, 0x60, 672, 131, 24, 25),
        KeyboardKey("Num9", 52, 0x61, 705, 131, 24, 25),
        KeyboardKey("NumPlus", 123, 0x57, 738, 131, 24, 59),
        KeyboardKey("CapsLock", 55, 0x39, 35, 164, 49, 25),
        KeyboardKey("A", 56, 0x04, 92, 164, 24, 25),
        KeyboardKey("S", 57, 0x16, 125, 164, 24, 25),
        KeyboardKey("D", 58, 0x07, 158, 164, 24, 25),
        KeyboardKey("F", 59, 0x09, 190, 164, 24, 25),
        KeyboardKey("G", 60, 0x0A, 223, 164, 24, 25),
        KeyboardKey("H", 61, 0x0B, 256, 164, 24, 25),
        KeyboardKey("J", 62, 0x0D, 288, 164, 24, 25),
        KeyboardKey("K", 63, 0x0E, 320, 164, 24, 25),
        KeyboardKey("L", 64, 0x0F, 353, 164, 24, 25),
        KeyboardKey("Semicolon", 65, 0x33, 385, 164, 24, 25),
        KeyboardKey("Quote", 66, 0x34, 418, 164, 24, 25),
        KeyboardKey("Enter", 85, 0x28, 451, 164, 65, 25),
        KeyboardKey("Num4", 68, 0x5C, 639, 164, 24, 25),
        KeyboardKey("Num5", 69, 0x5D, 672, 164, 24, 25),
        KeyboardKey("Num6", 70, 0x5E, 705, 164, 24, 25),
        KeyboardKey("LShift", 73, 0xE1, 35, 196, 65, 25),
        KeyboardKey("Z", 74, 0x1D, 108, 196, 24, 25),
        KeyboardKey("X", 75, 0x1B, 141, 196, 24, 25),
        KeyboardKey("C", 76, 0x06, 173, 196, 24, 25),
        KeyboardKey("V", 77, 0x19, 206, 196, 24, 25),
        KeyboardKey("B", 78, 0x05, 238, 196, 24, 25),
        KeyboardKey("N", 79, 0x11, 271, 196, 24, 25),
        KeyboardKey("M", 80, 0x10, 304, 196, 24, 25),
        KeyboardKey("Comma", 81, 0x36, 337, 196, 24, 25),
        KeyboardKey("Period", 82, 0x37, 369, 196, 24, 25),
        KeyboardKey("Slash", 83, 0x38, 401, 196, 24, 25),
        KeyboardKey("RShift", 84, 0xE5, 434, 196, 82, 25),
        KeyboardKey("Up", 101, 0x52, 565, 196, 24, 25),
        KeyboardKey("Num1", 86, 0x59, 639, 196, 24, 25),
        KeyboardKey("Num2", 87, 0x5A, 672, 196, 24, 25),
        KeyboardKey("Num3", 88, 0x5B, 705, 196, 24, 25),
        KeyboardKey("NumEnter", 106, 0x58, 738, 196, 24, 59),
        KeyboardKey("LCtrl", 91, 0xE0, 35, 230, 33, 25),
        KeyboardKey("LWin", 92, 0xE3, 76, 230, 33, 25),
        KeyboardKey("LAlt", 93, 0xE2, 117, 230, 33, 25),
        KeyboardKey("Space", 94, 0x2C, 159, 230, 191, 25),
        KeyboardKey("RAlt", 95, 0xE6, 360, 230, 33, 25),
        KeyboardKey("Fn", 96, 0xAF, 401, 230, 33, 25),
        KeyboardKey("Menu", 97, 0x65, 442, 230, 33, 25),
        KeyboardKey("RCtrl", 98, 0xE4, 482, 230, 33, 25),
        KeyboardKey("Left", 99, 0x50, 532, 230, 24, 25),
        KeyboardKey("Down", 100, 0x51, 565, 230, 24, 25),
        KeyboardKey("Right", 102, 0x4F, 598, 230, 24, 25),
        KeyboardKey("Num0", 104, 0x62, 639, 230, 57, 25),
        KeyboardKey("NumPeriod", 105, 0x63, 705, 230, 24, 25),
    ]

    static func key(named name: String) -> KeyboardKey? {
        keys.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func light(named name: String) -> UInt8? {
        key(named: name)?.light
    }
}

/// Custom per-key colours for an `rgb_keyboard="1"` layout: writer 0x44c5f0
/// (04 23) and reader 0x42b1e0 (04 F5), 4 bytes per light in 9 × 64 bytes.
enum PerKeyProtocol {
    static let chunkCount = BlockUpload.chunkCount
    static let blockLength = BlockUpload.blockLength

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
        return BlockUpload.packets(opcode: 0x23, block: block)
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
