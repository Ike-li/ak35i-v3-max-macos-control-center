import Foundation

enum KeymapLayer: CaseIterable, Equatable {
    case base
    case fn

    var opcode: UInt8 {
        switch self {
        case .base: return 0x11
        case .fn: return 0x27
        }
    }

    var displayName: String {
        switch self {
        case .base: return "普通层"
        case .fn: return "Fn 层"
        }
    }
}

/// Multimedia list of the driver (type 6, 0x4189ef–0x418a6b).
enum MediaKey: UInt8, CaseIterable {
    case playPause = 0xcd
    case stop = 0xb7
    case previous = 0xb6
    case next = 0xb5
    case volumeUp = 0xe9
    case volumeDown = 0xea
    case mute = 0xe2

    var cliName: String {
        switch self {
        case .playPause: return "playpause"
        case .stop: return "stop"
        case .previous: return "prev"
        case .next: return "next"
        case .volumeUp: return "volup"
        case .volumeDown: return "voldown"
        case .mute: return "mute"
        }
    }
}

/// Mouse list of the driver (type 5, 0x41891b–0x4189c7). Its double click
/// (`01 01 03 00`) is left out because it looks like left + right buttons.
enum MouseAction: CaseIterable {
    case left
    case right
    case middle
    case back
    case forward
    case wheelUp
    case wheelDown

    var cliName: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .middle: return "middle"
        case .back: return "back"
        case .forward: return "forward"
        case .wheelUp: return "wheelup"
        case .wheelDown: return "wheeldown"
        }
    }

    fileprivate var record: [UInt8] {
        switch self {
        case .left: return [0x01, 0x01, 0x01, 0x00]
        case .right: return [0x01, 0x01, 0x02, 0x00]
        case .middle: return [0x01, 0x01, 0x04, 0x00]
        case .back: return [0x01, 0x01, 0x08, 0x00]
        case .forward: return [0x01, 0x01, 0x10, 0x00]
        case .wheelUp: return [0x01, 0x03, 0x01, 0x00]
        case .wheelDown: return [0x01, 0x03, 0xff, 0x00]
        }
    }
}

enum KeyAction: Equatable {
    case defaultKey
    case disabled
    /// Left-modifier mask (Ctrl 1, Shift 2, Alt 4, Win 8) plus a HID usage.
    case key(modifiers: UInt8, usage: UInt8)
    case media(MediaKey)
    case mouse(MouseAction)

    /// One 4-byte slot of the 576-byte layer (0x4186d2–0x418bd3).
    var record: [UInt8] {
        switch self {
        case .defaultKey:
            return [0, 0, 0, 0]
        case .disabled:
            return [0x05, 0x03, 0x00, 0x00]
        case .key(let modifiers, let usage):
            if modifiers == 0, (0xe0...0xe7).contains(usage) {
                return [0x02, 1 << (usage - 0xe0), 0x00, 0x00]
            }
            return [0x02, modifiers, usage, 0x00]
        case .media(let key):
            return [0x03, key.rawValue, 0x00, 0x00]
        case .mouse(let action):
            return action.record
        }
    }
}

/// Key-map upload of DeviceDriver.exe 0x418590. The driver always sends a
/// whole layer, so keys missing from `assignments` revert to their default.
enum KeymapProtocol {
    static func packets(layer: KeymapLayer, assignments: [UInt8: KeyAction]) -> [FeaturePacket] {
        var block = [UInt8](repeating: 0, count: BlockUpload.blockLength)
        for (index, action) in assignments {
            let slot = 4 * Int(index)
            block.replaceSubrange(slot..<slot + 4, with: action.record)
        }
        return BlockUpload.packets(opcode: layer.opcode, block: block)
    }
}

extension KeyAction {
    private static let modifierBits: [String: UInt8] = [
        "ctrl": 0x01, "control": 0x01,
        "shift": 0x02,
        "alt": 0x04, "opt": 0x04, "option": 0x04,
        "win": 0x08, "cmd": 0x08, "command": 0x08,
    ]

    /// Parses `default`, `disabled`, `media:<name>`, `mouse:<name>`, a layout
    /// key name, a lone modifier word, or modifier words joined to one
    /// non-modifier key with `+`. Combinations the driver never produces,
    /// such as modifiers without a key, are rejected.
    init?(target: String) {
        let text = target.lowercased()
        switch text {
        case "default": self = .defaultKey; return
        case "disabled": self = .disabled; return
        default: break
        }
        if text.hasPrefix("media:") {
            guard let key = MediaKey.allCases.first(where: { "media:" + $0.cliName == text }) else { return nil }
            self = .media(key)
            return
        }
        if text.hasPrefix("mouse:") {
            guard let action = MouseAction.allCases.first(where: { "mouse:" + $0.cliName == text }) else { return nil }
            self = .mouse(action)
            return
        }

        var tokens = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let last = tokens.removeLast()
        if tokens.isEmpty, let bit = Self.modifierBits[last] {
            self = .key(modifiers: 0, usage: 0xe0 + UInt8(bit.trailingZeroBitCount))
            return
        }
        var modifiers: UInt8 = 0
        for token in tokens {
            guard let bit = Self.modifierBits[token], modifiers & bit == 0 else { return nil }
            modifiers |= bit
        }
        guard let key = KeyboardLayout.key(named: last), key.name != "Fn" else { return nil }
        if modifiers != 0, (0xe0...0xe7).contains(key.usage) { return nil }
        self = .key(modifiers: modifiers, usage: key.usage)
    }
}

struct KeymapRequest: Equatable {
    var layer: KeymapLayer = .base
    /// Keyed by key index, which equals the light index in this layout.
    var assignments: [UInt8: KeyAction] = [:]
}

extension KeyAction {
    /// Written in the target syntax so it can be typed back in.
    var displayName: String {
        switch self {
        case .defaultKey:
            return "default"
        case .disabled:
            return "disabled"
        case .key(let modifiers, let usage):
            let words = [(0x01, "Ctrl"), (0x02, "Shift"), (0x04, "Alt"), (0x08, "Cmd")]
                .filter { modifiers & UInt8($0.0) != 0 }
                .map(\.1)
            let key = KeyboardLayout.keys.first { $0.usage == usage }?.name ?? String(format: "0x%02X", usage)
            return (words + [key]).joined(separator: "+")
        case .media(let key):
            return "media:" + key.cliName
        case .mouse(let action):
            return "mouse:" + action.cliName
        }
    }
}

/// Key-map page state. The keyboard cannot be read, so the editor starts
/// empty and writing a layer sends exactly what it shows for that layer.
struct KeymapEditorState {
    var layer = KeymapLayer.base
    var selection: UInt8?
    private var layers: [KeymapLayer: [UInt8: KeyAction]] = [:]

    func action(for light: UInt8) -> KeyAction? {
        layers[layer]?[light]
    }

    /// Returns false when nothing is selected or the selection is Fn.
    @discardableResult
    mutating func assign(_ action: KeyAction) -> Bool {
        guard let selection, KeyboardLayout.keys.contains(where: { $0.light == selection && $0.name != "Fn" }) else {
            return false
        }
        layers[layer, default: [:]][selection] = action == .defaultKey ? nil : action
        return true
    }

    mutating func clearLayer() {
        layers[layer] = [:]
    }

    func request() -> KeymapRequest {
        KeymapRequest(layer: layer, assignments: layers[layer] ?? [:])
    }
}
