import Foundation

public enum LetheServiceControllerError: Error, LocalizedError {
    case launchAgentMissing(URL)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchAgentMissing(let url):
            return "LaunchAgent plist not found: \(url.path)"
        case .commandFailed(let output):
            return "launchctl command failed: \(output)"
        }
    }
}

public final class LetheServiceController {
    private let paths: LethePaths
    private let fileManager: FileManager

    public init(paths: LethePaths = LethePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    @discardableResult
    public func start() throws -> ShellCommandResult {
        try runLaunchctl(arguments: ["load", paths.launchAgentPlist.path])
    }

    @discardableResult
    public func stop() throws -> ShellCommandResult {
        try runLaunchctl(arguments: ["unload", paths.launchAgentPlist.path])
    }

    @discardableResult
    public func restart() throws -> ShellCommandResult {
        _ = try stop()
        return try start()
    }

    private func runLaunchctl(arguments: [String]) throws -> ShellCommandResult {
        guard fileManager.fileExists(atPath: paths.launchAgentPlist.path) else {
            throw LetheServiceControllerError.launchAgentMissing(paths.launchAgentPlist)
        }

        let result = try ShellCommand.run(
            executable: "/bin/launchctl",
            arguments: arguments,
            captureOutput: true
        )

        guard result.terminationStatus == 0 else {
            throw LetheServiceControllerError.commandFailed(
                [result.stderr, result.stdout].first(where: { !$0.isEmpty }) ?? "exit \(result.terminationStatus)"
            )
        }

        return result
    }
}
