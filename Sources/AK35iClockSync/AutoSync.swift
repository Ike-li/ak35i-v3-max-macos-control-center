import Foundation

struct AutoSyncLaunchAgentPlan {
    static let label = "dev.ak35i.controlcenter.clock-sync"
    let executablePath: String

    func propertyListData() throws -> Data {
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executablePath, "time", "sync", "--utc8", "--apply"],
            "RunAtLoad": true,
            "StartInterval": 86_400,
            "StandardOutPath": logDirectory.appendingPathComponent("AK35iClockSync.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("AK35iClockSync.log").path,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

enum AutoSyncStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? { "无法确定当前用户的 LaunchAgents 目录。" }
}

struct AutoSyncLaunchAgentStore {
    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    var url: URL { directory.appendingPathComponent("\(AutoSyncLaunchAgentPlan.label).plist") }

    func isEnabled() -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func enable(executablePath: String) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try AutoSyncLaunchAgentPlan(executablePath: executablePath).propertyListData().write(to: url, options: .atomic)
        return url
    }

    func disable() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
