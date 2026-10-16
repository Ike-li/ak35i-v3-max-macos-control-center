import Foundation

/// Data byte of the driver's mouse events (0x42de26–0x42de93).
enum MacroMouseButton: UInt8, CaseIterable {
    case left = 0x01
    case right = 0x02
    case middle = 0x04
}

enum MacroEvent: Equatable {
    case keyDown(UInt8)
    case keyUp(UInt8)
    case mouseDown(MacroMouseButton)
    case mouseUp(MacroMouseButton)

    /// Action entry of 0x42ddb9–0x42de93: data byte 2, tag byte 3.
    fileprivate var entry: [UInt8] {
        switch self {
        case .keyDown(let usage): return [0, 0, usage, 0xb0]
        case .keyUp(let usage): return [0, 0, usage, 0x30]
        case .mouseDown(let button): return [0, 0, button.rawValue, 0x90]
        case .mouseUp(let button): return [0, 0, button.rawValue, 0x10]
        }
    }
}

struct MacroStep: Equatable {
    var event: MacroEvent
    /// Milliseconds to wait after the event.
    var delay: Int
}

struct Macro: Equatable {
    var steps: [MacroStep]
}

/// Playback stored in the triggering key's record (`06 index mode count`).
/// The driver's mode 4 (点按播放) is left out: its behaviour is unknown.
enum MacroPlayback: Equatable {
    case once
    case times(UInt8)
    case untilPressedAgain
    case whileHeld

    var mode: UInt8 {
        switch self {
        case .once: return 0
        case .times: return 1
        case .untilPressedAgain: return 2
        case .whileHeld: return 3
        }
    }

    var count: UInt8 {
        if case .times(let count) = self { return count }
        return 0
    }

    var suffix: String {
        switch self {
        case .once: return ""
        case .times(let count): return ":x\(count)"
        case .untilPressedAgain: return ":toggle"
        case .whileHeld: return ":hold"
        }
    }
}

enum MacroError: LocalizedError, Equatable {
    case tooManyMacros(Int)
    case tooManyEvents(events: Int, macros: Int)
    case tooLargeForWireless(bytes: Int)

    var errorDescription: String? {
        switch self {
        case .tooManyMacros(let count):
            return "宏表最多 \(MacroProtocol.maxMacros) 个宏，当前 \(count) 个。"
        case .tooManyEvents(let events, let macros):
            return "宏太长：\(events) 个事件加 \(macros) 个宏超过驱动上限（两者之和最多 \(MacroProtocol.maxUnits)）。"
        case .tooLargeForWireless(let bytes):
            return "宏表有 \(bytes) 字节，经 2.4G 最多 \(MacroProtocol.maxWirelessTableEnd) 字节（再多会写进 Fn 层改键的存储区）。请减少事件，或用数据线连接后写入。"
        }
    }
}

/// Macro upload of DeviceDriver.exe 0x42db70. Every upload replaces the
/// whole table; there is no read command.
enum MacroProtocol {
    static let maxMacros = 100
    /// The driver refuses to send when 8 × (events + macros) > 0xA8C.
    static let maxUnits = 0xa8c / 8
    private static let tableStart = 0x190
    private static let bufferLength = 0xe00
    /// Firmware 0x69E4 writes 2.4G packets to 0xA000 + 28 × sequence and
    /// erases each 1 KB page it reaches; packet 110 would reach the Fn layer
    /// at 0xAC00, so at most 109 packets, which a table ending at 3024 fills.
    static let maxWirelessPackets = 109
    static let maxWirelessTableEnd = 3024

    static func packets(for macros: [Macro]) throws -> [FeaturePacket] {
        var (buffer, offset) = try table(for: macros)
        let chunkCount = offset / 64 + (offset % 64 == 0 ? 1 : 2)
        let length = chunkCount * 64
        buffer[length - 2] = 0xaa
        buffer[length - 1] = 0x55

        let chunks = (0..<chunkCount).map { index in
            FeaturePacket(report: [0] + buffer[index * 64..<(index + 1) * 64], expectsAck: false)
        }
        return [
            FeaturePacket(report: LightingProtocol.command(0x19), expectsAck: true),
            FeaturePacket(report: LightingProtocol.command(0x15, followingPackets: UInt8(chunkCount)), expectsAck: true),
        ] + chunks + [
            // The driver waits 35 ms after the last chunk plus Sleep(30).
            FeaturePacket(report: LightingProtocol.command(0x02), expectsAck: true, settleTime: 0.065),
        ]
    }

    /// DeviceDriver.exe 0x42e0f0: the same table in 28-byte packets, with the
    /// wired chunk-count rule, AA 55 at the end and E mod 28 as the last length.
    static func wirelessPackets(for macros: [Macro]) throws -> [[UInt8]] {
        var (buffer, end) = try table(for: macros)
        guard end <= maxWirelessTableEnd else { throw MacroError.tooLargeForWireless(bytes: end) }
        let count = end / 28 + (end % 28 == 0 ? 1 : 2)
        precondition(count <= maxWirelessPackets)
        buffer[count * 28 - 2] = 0xaa
        buffer[count * 28 - 1] = 0x55
        return (0..<count).map { (index: Int) -> [UInt8] in
            let length: UInt8 = index == count - 1 ? UInt8(end % 28) : 0x1c
            let data: [UInt8] = Array(buffer[index * 28..<(index + 1) * 28])
            return WirelessProtocol.packet(0x09, length: length, sequence: UInt8(index), data: data)
        }
    }

    /// The table of 0x42db70 and where it ends.
    private static func table(for macros: [Macro]) throws -> (buffer: [UInt8], end: Int) {
        let events = macros.reduce(0) { $0 + $1.steps.count }
        guard macros.count <= maxMacros else { throw MacroError.tooManyMacros(macros.count) }
        guard 8 * (events + macros.count) <= 0xa8c else {
            throw MacroError.tooManyEvents(events: events, macros: macros.count)
        }

        var buffer = [UInt8](repeating: 0, count: bufferLength)
        var offset = tableStart
        for (index, macro) in macros.enumerated() {
            guard !macro.steps.isEmpty else {
                buffer.replaceSubrange(4 * index..<4 * index + 4, with: [0xff, 0xff, 0xff, 0xff])
                continue
            }
            buffer[4 * index] = UInt8(offset & 0xff)
            buffer[4 * index + 1] = UInt8(offset >> 8)
            let entries = macro.steps.flatMap { step -> [UInt8] in
                let delay = max(step.delay, 10) & 0xffff
                return step.event.entry + [UInt8(delay & 0xff), UInt8(delay >> 8), 0, 0x50]
            }
            let count = entries.count / 4
            buffer[offset] = UInt8(count & 0xff)
            buffer[offset + 1] = UInt8(count >> 8)
            buffer.replaceSubrange(offset + 8..<offset + 8 + entries.count, with: entries)
            offset += 8 + entries.count
        }
        return (buffer, offset)
    }
}

struct MacroScriptError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

extension Macro {
    /// Not taken from the driver, which records real timings.
    static let defaultDelay = 20

    private enum Input: Equatable {
        case key(UInt8)
        case mouse(MacroMouseButton)

        func event(down: Bool) -> MacroEvent {
            switch self {
            case .key(let usage): return down ? .keyDown(usage) : .keyUp(usage)
            case .mouse(let button): return down ? .mouseDown(button) : .mouseUp(button)
            }
        }

        var name: String {
            switch self {
            case .key(let usage): return KeyboardLayout.keys.first { $0.usage == usage }?.name ?? String(format: "0x%02X", usage)
            case .mouse(let button): return "mouse:" + Self.mouseNames[button]!
            }
        }

        static let mouseNames: [MacroMouseButton: String] = [.left: "left", .right: "right", .middle: "middle"]

        init?(_ text: String) {
            let lower = text.lowercased()
            if lower.hasPrefix("mouse:") {
                guard let button = Self.mouseNames.first(where: { "mouse:" + $0.value == lower })?.key else { return nil }
                self = .mouse(button)
            } else if let bit = KeyAction.modifierBits[lower] {
                self = .key(0xe0 + UInt8(bit.trailingZeroBitCount))
            } else if let key = KeyboardLayout.key(named: text), key.name != "Fn" {
                self = .key(key.usage)
            } else {
                return nil
            }
        }
    }

    /// Comma-separated steps: `A` taps a key, `+A` / `-A` press or release
    /// it, `Cmd+Space` taps a chord, `mouse:left` clicks, and `100ms` sets the
    /// wait after the previous event. Every pressed input must be released.
    init(script: String) throws {
        var steps: [MacroStep] = []
        var held: [Input] = []
        func add(_ input: Input, down: Bool) throws {
            if down {
                guard !held.contains(input) else { throw MacroScriptError(message: "\(input.name) 已按下，不能再次按下。") }
                held.append(input)
            } else {
                guard let index = held.firstIndex(of: input) else { throw MacroScriptError(message: "\(input.name) 没有按下，不能松开。") }
                held.remove(at: index)
            }
            steps.append(MacroStep(event: input.event(down: down), delay: Macro.defaultDelay))
        }

        for raw in script.split(separator: ",", omittingEmptySubsequences: false) {
            let token = raw.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { throw MacroScriptError(message: "有空的步骤。") }

            if token.lowercased().hasSuffix("ms"), let delay = Int(token.dropLast(2)) {
                guard (10...0xffff).contains(delay) else { throw MacroScriptError(message: "等待时间须在 10–65535 ms。") }
                guard !steps.isEmpty else { throw MacroScriptError(message: "等待时间前面必须有按键。") }
                steps[steps.count - 1].delay = delay
            } else if let sign = token.first, sign == "+" || sign == "-" {
                guard let input = Input(String(token.dropFirst())) else { throw MacroScriptError(message: "无法识别 \(token)。") }
                try add(input, down: sign == "+")
            } else if token.contains("+") {
                let parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
                let modifiers = try parts.dropLast().map { part -> Input in
                    guard let bit = KeyAction.modifierBits[part.lowercased()] else {
                        throw MacroScriptError(message: "\(token)：+ 前面只能是 Ctrl、Shift、Alt、Cmd。")
                    }
                    return .key(0xe0 + UInt8(bit.trailingZeroBitCount))
                }
                guard KeyAction.modifierBits[parts.last!.lowercased()] == nil, let key = Input(parts.last!) else {
                    throw MacroScriptError(message: "\(token)：组合最后必须是一个普通键。")
                }
                for modifier in modifiers { try add(modifier, down: true) }
                try add(key, down: true)
                try add(key, down: false)
                for modifier in modifiers.reversed() { try add(modifier, down: false) }
            } else {
                guard let input = Input(token) else { throw MacroScriptError(message: "无法识别 \(token)。") }
                try add(input, down: true)
                try add(input, down: false)
            }
        }
        guard held.isEmpty else {
            throw MacroScriptError(message: "宏结束时 \(held.map(\.name).joined(separator: "、")) 仍按着，会卡键。")
        }
        self.steps = steps
    }

    /// The steps written back in the script syntax.
    var script: String {
        var tokens: [String] = []
        var index = 0
        while index < steps.count {
            let step = steps[index]
            let input: Input
            let down: Bool
            switch step.event {
            case .keyDown(let usage): input = .key(usage); down = true
            case .keyUp(let usage): input = .key(usage); down = false
            case .mouseDown(let button): input = .mouse(button); down = true
            case .mouseUp(let button): input = .mouse(button); down = false
            }
            var last = step
            if down, step.delay == Macro.defaultDelay, index + 1 < steps.count, steps[index + 1].event == input.event(down: false) {
                tokens.append(input.name)
                last = steps[index + 1]
                index += 1
            } else {
                tokens.append((down ? "+" : "-") + input.name)
            }
            if last.delay != Macro.defaultDelay { tokens.append("\(last.delay)ms") }
            index += 1
        }
        return tokens.joined(separator: ", ")
    }
}
