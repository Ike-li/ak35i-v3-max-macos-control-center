import Foundation

enum ClockTimeZone: Equatable {
    case utcPlusEight
    case system

    var timeZone: TimeZone {
        switch self {
        case .utcPlusEight: return TimeZone(secondsFromGMT: 8 * 60 * 60)!
        case .system: return .current
        }
    }

    var displayName: String {
        switch self {
        case .utcPlusEight: return "UTC+08:00"
        case .system: return timeZone.identifier
        }
    }
}

enum AutoSyncAction: Equatable {
    case status
    case enable
    case disable
}

enum AK35iCommand: Equatable {
    case help
    case gui
    case status(json: Bool)
    case timeSync(timeZone: ClockTimeZone, apply: Bool)
    case previewTime(timeZone: ClockTimeZone)
    case backup
    case restore
    case autoSync(AutoSyncAction)
    case lightingList
    case lightingSet(LightingEffect, apply: Bool)
    case perKeyList
    case perKeySet(PerKeyColorRequest, apply: Bool)
    case systemSet(SystemSettings, apply: Bool)
    case keymapSet(KeymapRequest, apply: Bool)
    case keymapReset([KeymapLayer], apply: Bool)
    case macroSet([Macro], apply: Bool)
    case live(LiveRequest)
    case screenSet(ScreenSource, preview: String?, apply: Bool)
    case battery
}

enum ScreenSource: Equatable {
    case file(String)
    case testPattern
}

enum AK35iCommandError: LocalizedError, Equatable {
    case invalidUsage(String)

    var errorDescription: String? {
        switch self {
        case .invalidUsage(let message): return message
        }
    }
}

enum AK35iCommandParser {
    static func parse(_ arguments: [String]) throws -> AK35iCommand {
        if arguments.isEmpty { return .help }
        if arguments.contains("--help") || arguments.contains("-h") { return .help }
        if arguments == ["--gui"] || arguments == ["gui"] { return .gui }

        // Compatibility with the first clock-only utility.
        if arguments.allSatisfy({ ["--apply", "--dry-run", "--utc8", "--utc+8"].contains($0) }) {
            return .timeSync(timeZone: parsedTimeZone(arguments), apply: arguments.contains("--apply") && !arguments.contains("--dry-run"))
        }

        switch arguments {
        case let values where values.first == "status":
            guard values.dropFirst().allSatisfy({ $0 == "--json" }) else {
                throw AK35iCommandError.invalidUsage("用法：ak35i status [--json]")
            }
            return .status(json: values.contains("--json"))
        case let values where values.starts(with: ["time", "sync"]):
            let options = Array(values.dropFirst(2))
            guard options.allSatisfy({ ["--apply", "--dry-run", "--utc8", "--utc+8"].contains($0) }) else {
                throw AK35iCommandError.invalidUsage("用法：ak35i time sync [--utc8] [--apply | --dry-run]")
            }
            return .timeSync(timeZone: parsedTimeZone(options), apply: options.contains("--apply") && !options.contains("--dry-run"))
        case let values where values.starts(with: ["preview", "time"]):
            let options = Array(values.dropFirst(2))
            guard options.allSatisfy({ ["--utc8", "--utc+8"].contains($0) }) else {
                throw AK35iCommandError.invalidUsage("用法：ak35i preview time [--utc8]")
            }
            return .previewTime(timeZone: parsedTimeZone(options))
        case ["battery"]:
            return .battery
        case ["backup"]:
            return .backup
        case ["restore"]:
            return .restore
        case ["autosync", "status"]:
            return .autoSync(.status)
        case let values where values.first == "autosync" && values.dropFirst().first == "enable":
            let options = Array(values.dropFirst(2))
            guard options.allSatisfy({ ["--utc8", "--utc+8"].contains($0) }) else {
                throw AK35iCommandError.invalidUsage("用法：ak35i autosync enable [--utc8]")
            }
            return .autoSync(.enable)
        case ["autosync", "disable"]:
            return .autoSync(.disable)
        case ["light", "list"]:
            return .lightingList
        case let values where values.starts(with: ["light", "set"]):
            return try parseLightingSet(Array(values.dropFirst(2)))
        case ["keys", "list"]:
            return .perKeyList
        case let values where values.starts(with: ["keys", "set"]):
            return try parsePerKeySet(Array(values.dropFirst(2)))
        case let values where values.starts(with: ["system", "set"]):
            return try parseSystemSet(Array(values.dropFirst(2)))
        case let values where values.starts(with: ["keymap", "set"]):
            return try parseKeymapSet(Array(values.dropFirst(2)))
        case let values where values.starts(with: ["keymap", "reset"]):
            return try parseKeymapReset(Array(values.dropFirst(2)))
        case let values where values.starts(with: ["macro", "set"]):
            return try parseMacros(Array(values.dropFirst(2)), allowEmpty: false)
        case let values where values.starts(with: ["macro", "clear"]):
            return try parseMacros(Array(values.dropFirst(2)), allowEmpty: true)
        case let values where values.starts(with: ["screen", "set"]):
            return try parseScreenSet(Array(values.dropFirst(2)))
        case let values where values.first == "live":
            return try parseLive(Array(values.dropFirst()))
        default:
            throw AK35iCommandError.invalidUsage("未知命令。运行 ak35i --help 查看可用命令。")
        }
    }

    private static func parsedTimeZone(_ arguments: [String]) -> ClockTimeZone {
        arguments.contains("--utc8") || arguments.contains("--utc+8") ? .utcPlusEight : .system
    }

    private static let lightingUsage = AK35iCommandError.invalidUsage(
        "用法：ak35i light set --mode <0-19> [--brightness 0-5] [--speed 0-5] [--direction N] [--color RRGGBB | --colorful] [--apply]"
    )

    private static func parseLightingSet(_ options: [String]) throws -> AK35iCommand {
        var mode: LightingMode?
        var brightness: Int?
        var speed: Int?
        var direction: Int?
        var color: LightingColor?
        var apply = false

        var remaining = options[...]
        while let option = remaining.popFirst() {
            switch option {
            case "--apply":
                apply = true
            case "--colorful":
                guard color == nil else { throw lightingUsage }
                color = .colorful
            case "--color":
                guard color == nil, let value = remaining.popFirst(), let rgb = hexColor(value) else { throw lightingUsage }
                color = .solid(rgb)
            case "--mode", "--brightness", "--speed", "--direction":
                guard let value = remaining.popFirst().flatMap({ Int($0) }) else { throw lightingUsage }
                switch option {
                case "--mode":
                    guard let parsed = UInt8(exactly: value).flatMap(LightingMode.init(rawValue:)) else {
                        throw AK35iCommandError.invalidUsage("灯效模式必须是 0–19。运行 ak35i light list 查看。")
                    }
                    mode = parsed
                case "--brightness": brightness = value
                case "--speed": speed = value
                default: direction = value
                }
            default:
                throw lightingUsage
            }
        }

        guard let mode else { throw lightingUsage }
        let effect = try LightingEffect(mode: mode, brightness: brightness, speed: speed, direction: direction, color: color)
        return .lightingSet(effect, apply: apply)
    }

    private static let perKeyUsage = AK35iCommandError.invalidUsage(
        "用法：ak35i keys set [键名=RRGGBB ...] [--all RRGGBB] [--clear] [--brightness 0-5] [--apply]"
    )

    private static func parsePerKeySet(_ options: [String]) throws -> AK35iCommand {
        var request = PerKeyColorRequest()
        var apply = false

        var remaining = options[...]
        while let option = remaining.popFirst() {
            switch option {
            case "--apply":
                apply = true
            case "--clear":
                request.clear = true
            case "--all":
                guard request.all == nil, let value = remaining.popFirst(), let rgb = hexColor(value) else { throw perKeyUsage }
                request.all = rgb
            case "--brightness":
                guard let value = remaining.popFirst().flatMap({ Int($0) }) else { throw perKeyUsage }
                guard LightingEffect.levels.contains(value) else {
                    throw LightingEffectError.outOfRange(.brightness, value: value, allowed: LightingEffect.levels)
                }
                request.brightness = value
            default:
                let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, let rgb = hexColor(parts[1]) else { throw perKeyUsage }
                guard let light = KeyboardLayout.light(named: parts[0]) else {
                    throw AK35iCommandError.invalidUsage("未知按键 \(parts[0])。运行 ak35i keys list 查看可用键名。")
                }
                guard request.keys[light] == nil else {
                    throw AK35iCommandError.invalidUsage("按键 \(parts[0]) 重复指定。")
                }
                request.keys[light] = rgb
            }
        }

        guard request.clear || request.all != nil || !request.keys.isEmpty else { throw perKeyUsage }
        return .perKeySet(request, apply: apply)
    }

    private static let systemUsage = AK35iCommandError.invalidUsage(
        "用法：ak35i system set [--sleep never|1m|5m|30m] [--response 1-5] [--disable-win on|off] [--disable-alt-tab on|off] [--disable-alt-f4 on|off] [--fn-switch 0|1] [--apply]"
    )

    private static func parseSystemSet(_ options: [String]) throws -> AK35iCommand {
        var settings = SystemSettings()
        var apply = false
        var seen: Set<String> = []

        var remaining = options[...]
        while let option = remaining.popFirst() {
            if option == "--apply" {
                apply = true
                continue
            }
            guard seen.insert(option).inserted, let value = remaining.popFirst() else { throw systemUsage }
            switch option {
            case "--sleep":
                guard let sleep = SleepTimeout.allCases.first(where: { $0.cliName == value }) else { throw systemUsage }
                settings.sleep = sleep
            case "--response":
                guard let level = Int(value), SystemSettings.responseLevels.contains(level) else { throw systemUsage }
                settings.responseLevel = level
            case "--fn-switch":
                guard let fn = Int(value), [0, 1].contains(fn) else { throw systemUsage }
                settings.fnSwitch = fn
            case "--disable-win", "--disable-alt-tab", "--disable-alt-f4":
                guard ["on", "off"].contains(value) else { throw systemUsage }
                let disabled = value == "on"
                switch option {
                case "--disable-win": settings.disableWin = disabled
                case "--disable-alt-tab": settings.disableAltTab = disabled
                default: settings.disableAltF4 = disabled
                }
            default:
                throw systemUsage
            }
        }
        return .systemSet(settings, apply: apply)
    }

    private static let keymapUsage = AK35iCommandError.invalidUsage(
        "用法：ak35i keymap set [--layer base|fn] 键名=目标 ... [--apply]；目标为键名、Ctrl+Shift+C 这类组合、Ctrl/Shift/Alt/Cmd、media:名称、mouse:名称、disabled 或 default。运行 ak35i --help 查看。"
    )

    private static func parseKeymapSet(_ options: [String]) throws -> AK35iCommand {
        var request = KeymapRequest()
        var apply = false
        var layerGiven = false

        var remaining = options[...]
        while let option = remaining.popFirst() {
            switch option {
            case "--apply":
                apply = true
            case "--layer":
                guard !layerGiven, let value = remaining.popFirst(), let layer = keymapLayer(value) else { throw keymapUsage }
                layerGiven = true
                request.layer = layer
            default:
                let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw keymapUsage }
                guard let key = KeyboardLayout.key(named: parts[0]) else {
                    throw AK35iCommandError.invalidUsage("未知按键 \(parts[0])。运行 ak35i keys list 查看可用键名。")
                }
                guard key.name != "Fn" else {
                    throw AK35iCommandError.invalidUsage("不能改 Fn 键本身，否则可能无法再进入 Fn 层。")
                }
                guard let action = KeyAction(target: parts[1]) else {
                    throw AK35iCommandError.invalidUsage("无法识别的目标 \(parts[1])。")
                }
                guard request.assignments[key.light] == nil else {
                    throw AK35iCommandError.invalidUsage("按键 \(parts[0]) 重复指定。")
                }
                request.assignments[key.light] = action
            }
        }
        guard !request.assignments.isEmpty else { throw keymapUsage }
        return .keymapSet(request, apply: apply)
    }

    private static func parseKeymapReset(_ options: [String]) throws -> AK35iCommand {
        let usage = AK35iCommandError.invalidUsage("用法：ak35i keymap reset [--layer base|fn] [--apply]")
        var layers = KeymapLayer.allCases
        var apply = false
        var remaining = options[...]
        while let option = remaining.popFirst() {
            switch option {
            case "--apply":
                apply = true
            case "--layer":
                guard layers.count == KeymapLayer.allCases.count, let value = remaining.popFirst(), let layer = keymapLayer(value) else { throw usage }
                layers = [layer]
            default:
                throw usage
            }
        }
        return .keymapReset(layers, apply: apply)
    }

    private static func parseMacros(_ options: [String], allowEmpty: Bool) throws -> AK35iCommand {
        let apply = options.contains("--apply")
        let scripts = options.filter { $0 != "--apply" }
        guard allowEmpty ? scripts.isEmpty : !scripts.isEmpty else {
            throw AK35iCommandError.invalidUsage("用法：ak35i macro set \"宏1\" [\"宏2\" ...] [--apply]，或 ak35i macro clear [--apply]")
        }
        let macros = try scripts.enumerated().map { index, script in
            do {
                return try Macro(script: script)
            } catch {
                throw AK35iCommandError.invalidUsage("宏 \(index + 1)：\(error.localizedDescription)")
            }
        }
        return .macroSet(macros, apply: apply)
    }

    private static let liveUsage = AK35iCommandError.invalidUsage(
        "用法：ak35i live static|starlight|fluttering|breathing|fountain|wave|currents|rotating [--color RRGGBB] [--speed 1-15] [--seconds N]（给颜色即为单色，否则多彩；fluttering 不取颜色，static 不取速度）\n"
            + "     ak35i live music [--foreground 模式] [--background 模式|off] [--amplitude 0-100] [--background-brightness 0-100] [--seconds N]\n"
            + "     模式：" + DriverMusicMode.backgrounds.map(\.cliName).joined(separator: "、")
    )

    private static func parseLive(_ options: [String]) throws -> AK35iCommand {
        var remaining = options[...]
        let aliases = ["solid": "static", "starry": "starlight"]
        guard let given = remaining.popFirst() else { throw liveUsage }
        let name = aliases[given] ?? given
        let effect: LiveEffect
        if name == "music" {
            effect = .music
        } else if let driver = DriverLightEffect.allCases.first(where: { $0.cliName == name }) {
            effect = .driver(driver)
        } else {
            throw liveUsage
        }
        var request = LiveRequest(effect: effect)
        var seen: Set<String> = []
        while let option = remaining.popFirst() {
            guard !seen.contains(option) else { throw liveUsage }
            seen.insert(option)
            switch option {
            case "--color":
                guard case .driver(let driver) = effect, driver.takesColor,
                      let value = remaining.popFirst(), let rgb = hexColor(value) else { throw liveUsage }
                request.color = rgb
                request.colorful = false
            case "--speed":
                guard case .driver(let driver) = effect, driver.takesSpeed,
                      let value = remaining.popFirst().flatMap({ Int($0) }), LiveAnimation.speeds.contains(value) else { throw liveUsage }
                request.speed = value
            case "--seconds":
                guard let value = remaining.popFirst().flatMap({ Int($0) }), value > 0 else { throw liveUsage }
                request.seconds = value
            case "--foreground", "--background":
                let modes = option == "--foreground" ? DriverMusicMode.foregrounds : DriverMusicMode.backgrounds
                guard effect == .music, let value = remaining.popFirst(),
                      let mode = modes.first(where: { $0.cliName == value }) else { throw liveUsage }
                if option == "--foreground" { request.music.foreground = mode } else { request.music.background = mode }
            case "--amplitude", "--background-brightness":
                guard effect == .music, let value = remaining.popFirst().flatMap({ Int($0) }),
                      DriverMusicSettings.range.contains(value) else { throw liveUsage }
                if option == "--amplitude" { request.music.amplitude = value } else { request.music.backgroundBrightness = value }
            default:
                throw liveUsage
            }
        }
        return .live(request)
    }

    private static func parseScreenSet(_ options: [String]) throws -> AK35iCommand {
        let usage = AK35iCommandError.invalidUsage("用法：ak35i screen set <图片或 GIF> | --test-pattern [--preview 预览.png] [--apply]")
        var source: ScreenSource?
        var preview: String?
        var apply = false
        var remaining = options[...]
        while let option = remaining.popFirst() {
            switch option {
            case "--apply":
                apply = true
            case "--test-pattern":
                guard source == nil else { throw usage }
                source = .testPattern
            case "--preview":
                guard preview == nil, let value = remaining.popFirst() else { throw usage }
                preview = value
            default:
                guard source == nil, !option.hasPrefix("--") else { throw usage }
                source = .file(option)
            }
        }
        guard let source else { throw usage }
        return .screenSet(source, preview: preview, apply: apply)
    }

    private static func keymapLayer(_ value: String) -> KeymapLayer? {
        switch value {
        case "base": return .base
        case "fn": return .fn
        default: return nil
        }
    }

    private static func hexColor(_ text: String) -> RGBColor? {
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { return nil }
        return RGBColor(red: UInt8(value >> 16), green: UInt8((value >> 8) & 0xff), blue: UInt8(value & 0xff))
    }
}

enum AK35iLaunchContext {
    /// Finder appends a process serial number when launching a bundle. It is
    /// not a CLI option and must open the graphical control center instead of
    /// being treated as an unknown command.
    static func command(from rawArguments: [String], executablePath: String? = nil) throws -> AK35iCommand {
        let launchedFromFinder = rawArguments.contains { $0.hasPrefix("-psn_") }
        let cliArguments = rawArguments.filter { !$0.hasPrefix("-psn_") }
        if launchedFromFinder && cliArguments.isEmpty { return .gui }
        if cliArguments.isEmpty && isAppBundleExecutable(executablePath) { return .gui }
        return try AK35iCommandParser.parse(cliArguments)
    }

    private static func isAppBundleExecutable(_ executablePath: String?) -> Bool {
        guard let executablePath else { return false }
        let path = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        return path.contains(".app/Contents/MacOS/")
    }
}
