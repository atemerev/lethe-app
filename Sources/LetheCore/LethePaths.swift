import Foundation

public struct LethePaths {
    public var homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var repositoryRoot: URL {
        homeDirectory.appending(path: "devel/lethe", directoryHint: .isDirectory)
    }

    public var installScript: URL {
        repositoryRoot.appending(path: "install.sh", directoryHint: .notDirectory)
    }

    public var updateScript: URL {
        repositoryRoot.appending(path: "update.sh", directoryHint: .notDirectory)
    }

    public var uninstallScript: URL {
        repositoryRoot.appending(path: "uninstall.sh", directoryHint: .notDirectory)
    }

    public var launchAgentPlist: URL {
        homeDirectory.appending(path: "Library/LaunchAgents/com.lethe.agent.plist", directoryHint: .notDirectory)
    }

    public var installDirectory: URL {
        homeDirectory.appending(path: ".lethe", directoryHint: .isDirectory)
    }

    public var configDirectory: URL {
        homeDirectory.appending(path: ".config/lethe", directoryHint: .isDirectory)
    }

    public var workspaceDirectory: URL {
        homeDirectory.appending(path: "lethe", directoryHint: .isDirectory)
    }

    public var launchdStdoutLogPath: URL {
        homeDirectory.appending(path: "Library/Logs/lethe.log", directoryHint: .notDirectory)
    }

    public var launchdStderrLogPath: URL {
        homeDirectory.appending(path: "Library/Logs/lethe.error.log", directoryHint: .notDirectory)
    }
}
