import Foundation

public enum LetheNativeInstallerError: Error, LocalizedError {
    case missingDependency(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingDependency(let name):
            return "Missing dependency: \(name). Install it and retry."
        case .installFailed(let details):
            return details
        }
    }
}

public struct LetheInstallResult {
    public let installDirectory: URL
    public let configFile: URL
    public let launchAgent: URL
}

public final class LetheNativeInstaller: @unchecked Sendable {
    private struct ToolDependency {
        let command: String
        let brewPackage: String
    }

    private let paths: LethePaths
    private let fileManager: FileManager
    private let toolSearchPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    public init(paths: LethePaths = LethePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func install(config: LetheInstallConfiguration) throws -> LetheInstallResult {
        try ensureDependencies()
        try cloneOrUpdateRepository()
        try ensureRuntimeDependencies()
        let envFile = try writeEnvironment(config: config)
        try installPythonDependencies()
        try setupLaunchAgent()

        return LetheInstallResult(
            installDirectory: paths.installDirectory,
            configFile: envFile,
            launchAgent: paths.launchAgentPlist
        )
    }

    public func uninstall() throws {
        _ = try? ShellCommand.run(
            executable: "/bin/launchctl",
            arguments: ["unload", paths.launchAgentPlist.path]
        )

        if fileManager.fileExists(atPath: paths.launchAgentPlist.path) {
            try fileManager.removeItem(at: paths.launchAgentPlist)
        }

        if fileManager.fileExists(atPath: paths.installDirectory.path) {
            try fileManager.removeItem(at: paths.installDirectory)
        }
    }

    private func ensureDependencies() throws {
        let dependencies = [
            ToolDependency(command: "git", brewPackage: "git"),
            ToolDependency(command: "uv", brewPackage: "uv"),
            ToolDependency(command: "npm", brewPackage: "node"),
        ]

        for dependency in dependencies {
            if commandExists(dependency.command) {
                continue
            }
            try installDependencyWithHomebrew(dependency)
        }
    }

    private func ensureRuntimeDependencies() throws {
        if !commandExists("agent-browser") {
            _ = try runChecked(
                executable: "/usr/bin/env",
                arguments: ["npm", "install", "-g", "agent-browser"]
            )
            guard commandExists("agent-browser") else {
                throw LetheNativeInstallerError.installFailed(
                    "Installed agent-browser, but command is still unavailable in PATH."
                )
            }
        }

        _ = try runChecked(
            executable: "/usr/bin/env",
            arguments: ["agent-browser", "install", "--with-deps"]
        )
    }

    private func cloneOrUpdateRepository() throws {
        if fileManager.fileExists(atPath: paths.installDirectory.appending(path: ".git").path) {
            _ = try runChecked(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", paths.installDirectory.path, "fetch", "origin", "--tags"]
            )
            _ = try runChecked(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", paths.installDirectory.path, "checkout", "main"]
            )
            _ = try runChecked(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", paths.installDirectory.path, "pull", "origin", "main"]
            )
        } else {
            try fileManager.createDirectory(
                at: paths.installDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            _ = try runChecked(
                executable: "/usr/bin/env",
                arguments: ["git", "clone", "https://github.com/atemerev/lethe.git", paths.installDirectory.path]
            )
        }
    }

    private func writeEnvironment(config: LetheInstallConfiguration) throws -> URL {
        try fileManager.createDirectory(
            at: paths.configDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            at: paths.workspaceDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let envFile = paths.configDirectory.appending(path: ".env", directoryHint: .notDirectory)
        var lines: [String] = []
        lines.append("# Lethe Configuration")
        lines.append("# Generated by lethe-app on \(Date())")
        lines.append("")
        lines.append("# Telegram")
        lines.append("TELEGRAM_BOT_TOKEN=\(config.telegramBotToken)")
        lines.append("TELEGRAM_ALLOWED_USER_IDS=\(config.telegramUserID)")
        lines.append("")
        lines.append("# LLM")
        lines.append("LLM_PROVIDER=\(config.provider.rawValue)")
        lines.append("LLM_MODEL=\(config.model)")
        lines.append("LLM_MODEL_AUX=\(config.auxModel)")
        lines.append("LLM_API_BASE=\(config.apiBase)")
        lines.append("\(config.authEnvName)=\(config.apiKey)")
        lines.append("")
        lines.append("# Paths")
        lines.append("WORKSPACE_DIR=\(paths.workspaceDirectory.path)")
        lines.append("MEMORY_DIR=\(paths.workspaceDirectory.appending(path: "data/memory").path)")
        lines.append("")
        lines.append("HEARTBEAT_ENABLED=true")
        lines.append("HIPPOCAMPUS_ENABLED=true")

        try lines.joined(separator: "\n").write(to: envFile, atomically: true, encoding: .utf8)

        let installEnv = paths.installDirectory.appending(path: ".env", directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: installEnv.path) {
            try fileManager.removeItem(at: installEnv)
        }
        try fileManager.createSymbolicLink(at: installEnv, withDestinationURL: envFile)
        return envFile
    }

    private func installPythonDependencies() throws {
        _ = try runChecked(
            executable: "/usr/bin/env",
            arguments: ["uv", "sync"],
            currentDirectory: paths.installDirectory
        )
    }

    private func setupLaunchAgent() throws {
        let uvPath = try resolveBinaryPath("uv")

        let launchAgentsDirectory = paths.launchAgentPlist.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.lethe.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(uvPath)</string>
                <string>run</string>
                <string>lethe</string>
            </array>
            <key>WorkingDirectory</key>
            <string>\(paths.installDirectory.path)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(paths.launchdStdoutLogPath.path)</string>
            <key>StandardErrorPath</key>
            <string>\(paths.launchdStderrLogPath.path)</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\((uvPath as NSString).deletingLastPathComponent):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
            </dict>
        </dict>
        </plist>
        """

        try plist.write(to: paths.launchAgentPlist, atomically: true, encoding: .utf8)

        _ = try? ShellCommand.run(
            executable: "/bin/launchctl",
            arguments: ["unload", paths.launchAgentPlist.path]
        )
        _ = try runChecked(
            executable: "/bin/launchctl",
            arguments: ["load", paths.launchAgentPlist.path]
        )
    }

    private func resolveBinaryPath(_ command: String) throws -> String {
        for directory in toolSearchPath.split(separator: ":") {
            let candidate = String(directory) + "/" + command
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        let result = try runChecked(
            executable: "/usr/bin/env",
            arguments: ["which", command]
        )
        return result.stdout
    }

    @discardableResult
    private func runChecked(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> ShellCommandResult {
        let result = try ShellCommand.run(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: shellEnvironment
        )
        guard result.terminationStatus == 0 else {
            let details = [result.stderr, result.stdout]
                .first(where: { !$0.isEmpty }) ?? "Command failed: \(executable) \(arguments.joined(separator: " "))"
            throw LetheNativeInstallerError.installFailed(details)
        }
        return result
    }

    private func commandExists(_ command: String) -> Bool {
        guard
            let result = try? ShellCommand.run(
                executable: "/usr/bin/env",
                arguments: ["which", command],
                environment: shellEnvironment
            )
        else {
            return false
        }
        return result.terminationStatus == 0 && !result.stdout.isEmpty
    }

    private var shellEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.merging(["PATH": toolSearchPath]) { _, newValue in
            newValue
        }
    }

    private func installDependencyWithHomebrew(_ dependency: ToolDependency) throws {
        let brewPath = try resolveHomebrewPath()

        if !isHomebrewPackageInstalled(dependency.brewPackage, brewPath: brewPath) {
            _ = try runChecked(
                executable: brewPath,
                arguments: ["install", dependency.brewPackage]
            )
        }

        guard commandExists(dependency.command) else {
            throw LetheNativeInstallerError.installFailed(
                "Installed \(dependency.brewPackage), but \(dependency.command) is still unavailable."
            )
        }
    }

    private func isHomebrewPackageInstalled(_ package: String, brewPath: String) -> Bool {
        guard
            let result = try? ShellCommand.run(
                executable: brewPath,
                arguments: ["list", "--versions", package],
                environment: shellEnvironment
            )
        else {
            return false
        }
        return result.terminationStatus == 0 && !result.stdout.isEmpty
    }

    private func resolveHomebrewPath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        if let result = try? ShellCommand.run(
            executable: "/usr/bin/env",
            arguments: ["which", "brew"],
            environment: shellEnvironment
        ),
           result.terminationStatus == 0,
           !result.stdout.isEmpty {
            return result.stdout
        }

        throw LetheNativeInstallerError.missingDependency(
            "Homebrew (brew). Install from https://brew.sh and retry."
        )
    }
}
