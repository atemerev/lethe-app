import Foundation

public struct LetheRuntimeStatus {
    public let repoAvailable: Bool
    public let installed: Bool
    public let launchAgentInstalled: Bool
    public let launchAgentLoaded: Bool
    public let launchAgentRunning: Bool
    public let launchAgentPID: Int?

    public init(
        repoAvailable: Bool,
        installed: Bool,
        launchAgentInstalled: Bool,
        launchAgentLoaded: Bool,
        launchAgentRunning: Bool,
        launchAgentPID: Int?
    ) {
        self.repoAvailable = repoAvailable
        self.installed = installed
        self.launchAgentInstalled = launchAgentInstalled
        self.launchAgentLoaded = launchAgentLoaded
        self.launchAgentRunning = launchAgentRunning
        self.launchAgentPID = launchAgentPID
    }
}

public final class LetheStatusProbe {
    private let paths: LethePaths
    private let fileManager: FileManager

    public init(paths: LethePaths = LethePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func currentStatus() -> LetheRuntimeStatus {
        let repoAvailable = fileManager.fileExists(atPath: paths.repositoryRoot.path)
        let installDirectoryExists = fileManager.fileExists(atPath: paths.installDirectory.path)
        let installGitExists = fileManager.fileExists(
            atPath: paths.installDirectory.appending(path: ".git", directoryHint: .isDirectory).path
        )
        let configEnvExists = fileManager.fileExists(
            atPath: paths.configDirectory.appending(path: ".env", directoryHint: .notDirectory).path
        )
        let installed = installDirectoryExists && installGitExists && configEnvExists
        let launchAgentInstalled = fileManager.fileExists(atPath: paths.launchAgentPlist.path)
        let launchAgentState = readLaunchAgentState()

        return LetheRuntimeStatus(
            repoAvailable: repoAvailable,
            installed: installed,
            launchAgentInstalled: launchAgentInstalled,
            launchAgentLoaded: launchAgentState.loaded,
            launchAgentRunning: launchAgentState.running,
            launchAgentPID: launchAgentState.pid
        )
    }

    private func readLaunchAgentState() -> (loaded: Bool, running: Bool, pid: Int?) {
        let uid = getuid()
        let target = "gui/\(uid)/com.lethe.agent"

        if
            let result = try? ShellCommand.run(
                executable: "/bin/launchctl",
                arguments: ["print", target],
                captureOutput: true
            ),
            result.terminationStatus == 0
        {
            let pid = parsePID(from: result.stdout)
            let running = result.stdout.contains("state = running") || (pid ?? 0) > 0
            return (loaded: true, running: running, pid: pid)
        }

        guard
            let result = try? ShellCommand.run(
                executable: "/bin/launchctl",
                arguments: ["list"],
                captureOutput: true
            ),
            result.terminationStatus == 0
        else {
            return (loaded: false, running: false, pid: nil)
        }

        let loaded = result.stdout.contains("com.lethe.agent")
        return (loaded: loaded, running: false, pid: nil)
    }

    private func parsePID(from output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid = ") else {
                continue
            }
            let value = trimmed.replacingOccurrences(of: "pid = ", with: "")
            if let pid = Int(value), pid > 0 {
                return pid
            }
        }
        return nil
    }
}
