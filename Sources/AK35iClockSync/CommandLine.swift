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
}

enum AK35iCommandError: LocalizedError, Equatable {
    case invalidUsage(String)
    case featureRequiresCapture(AK35iFeature)

    var errorDescription: String? {
        switch self {
        case .invalidUsage(let message): return message
        case .featureRequiresCapture(let feature):
            return "\(feature.displayName) 尚未取得 V3 Max 的抓包验证，安全策略已阻止写入。"
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
        case let values where values.starts(with: ["apply", "screen"]):
            throw AK35iCommandError.featureRequiresCapture(.screenUpload)
        case let values where values.starts(with: ["apply", "lighting"]):
            throw AK35iCommandError.featureRequiresCapture(.lighting)
        case let values where values.starts(with: ["apply", "keymap"]):
            throw AK35iCommandError.featureRequiresCapture(.keymap)
        case let values where values.starts(with: ["apply", "macro"]):
            throw AK35iCommandError.featureRequiresCapture(.macros)
        default:
            throw AK35iCommandError.invalidUsage("未知命令。运行 ak35i --help 查看可用命令。")
        }
    }

    private static func parsedTimeZone(_ arguments: [String]) -> ClockTimeZone {
        arguments.contains("--utc8") || arguments.contains("--utc+8") ? .utcPlusEight : .system
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
