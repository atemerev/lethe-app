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
    private let launchAgentLabel = "com.lethe.agent"
    private let paths: LethePaths
    private let fileManager: FileManager

    public init(paths: LethePaths = LethePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    @discardableResult
    public func start() throws -> ShellCommandResult {
        let loadResult = try runLaunchctl(
            arguments: ["load", paths.launchAgentPlist.path],
            toleratedErrors: ["already loaded"]
        )
        _ = try? runLaunchctl(
            arguments: ["kickstart", "-k", launchctlDomainTarget],
            toleratedErrors: ["Could not find service", "No such process"]
        )
        return loadResult
    }

    @discardableResult
    public func stop() throws -> ShellCommandResult {
        try runLaunchctl(
            arguments: ["unload", paths.launchAgentPlist.path],
            toleratedErrors: ["Could not find service", "No such process", "not loaded"]
        )
    }

    @discardableResult
    public func restart() throws -> ShellCommandResult {
        _ = try stop()
        return try start()
    }

    private var launchctlDomainTarget: String {
        "gui/\(getuid())/\(launchAgentLabel)"
    }

    private func runLaunchctl(
        arguments: [String],
        toleratedErrors: [String] = []
    ) throws -> ShellCommandResult {
        guard fileManager.fileExists(atPath: paths.launchAgentPlist.path) else {
            throw LetheServiceControllerError.launchAgentMissing(paths.launchAgentPlist)
        }

        let result = try ShellCommand.run(
            executable: "/bin/launchctl",
            arguments: arguments,
            captureOutput: true
        )

        let output = [result.stderr, result.stdout].first(where: { !$0.isEmpty }) ?? ""
        guard result.terminationStatus == 0 else {
            let lowercasedOutput = output.lowercased()
            if toleratedErrors.contains(where: { lowercasedOutput.contains($0.lowercased()) }) {
                return result
            }
            throw LetheServiceControllerError.commandFailed(output.isEmpty ? "exit \(result.terminationStatus)" : output)
        }

        return result
    }
}
