import Foundation

public struct LetheRuntimeStatus {
    public let repoAvailable: Bool
    public let installed: Bool
    public let launchAgentInstalled: Bool
    public let launchAgentLoaded: Bool

    public init(
        repoAvailable: Bool,
        installed: Bool,
        launchAgentInstalled: Bool,
        launchAgentLoaded: Bool
    ) {
        self.repoAvailable = repoAvailable
        self.installed = installed
        self.launchAgentInstalled = launchAgentInstalled
        self.launchAgentLoaded = launchAgentLoaded
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
        let installed = fileManager.fileExists(atPath: paths.installDirectory.path)
        let launchAgentInstalled = fileManager.fileExists(atPath: paths.launchAgentPlist.path)
        let launchAgentLoaded = isLaunchAgentLoaded()

        return LetheRuntimeStatus(
            repoAvailable: repoAvailable,
            installed: installed,
            launchAgentInstalled: launchAgentInstalled,
            launchAgentLoaded: launchAgentLoaded
        )
    }

    private func isLaunchAgentLoaded() -> Bool {
        guard
            let result = try? ShellCommand.run(
                executable: "/bin/launchctl",
                arguments: ["list"],
                captureOutput: true
            ),
            result.terminationStatus == 0
        else {
            return false
        }

        return result.stdout.contains("com.lethe.agent")
    }
}
