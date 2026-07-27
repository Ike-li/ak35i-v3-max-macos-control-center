import Foundation

@main
@MainActor
struct AK35iMain {
    static func main() {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path

        do {
            let command = try AK35iLaunchContext.command(
                from: rawArguments,
                executablePath: executablePath
            )
            if command == .gui {
                startControlCenter(executablePath: executablePath)
            } else {
                exit(AK35iApplication.run(command, executablePath: executablePath))
            }
        } catch {
            fputs("错误：\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
