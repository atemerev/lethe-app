import Foundation

public enum LetheScriptAction: String, CaseIterable {
    case install
    case update
    case uninstall

    public var title: String {
        switch self {
        case .install:
            return "Install Lethe"
        case .update:
            return "Update Lethe"
        case .uninstall:
            return "Uninstall Lethe"
        }
    }
}

public enum LetheScriptRunnerError: Error, LocalizedError {
    case scriptMissing(URL)
    case osascriptFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .scriptMissing(let url):
            return "Script not found: \(url.path)"
        case .osascriptFailed(let code, let details):
            if details.isEmpty {
                return "Failed to open script in Terminal (exit \(code))."
            }
            return "Failed to open script in Terminal (exit \(code)): \(details)"
        }
    }
}

public final class LetheScriptRunner {
    private let paths: LethePaths
    private let fileManager: FileManager

    public init(paths: LethePaths = LethePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func runInTerminal(action: LetheScriptAction, additionalArguments: [String] = []) throws {
        let script = scriptURL(for: action)
        guard fileManager.fileExists(atPath: script.path) else {
            throw LetheScriptRunnerError.scriptMissing(script)
        }

        var commandParts = ["/bin/zsh", shellEscape(script.path)]
        commandParts.append(contentsOf: additionalArguments.map(shellEscape))
        let command = "cd \(shellEscape(paths.repositoryRoot.path)) && \(commandParts.joined(separator: " "))"

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(escapeForAppleScript(command))"
        end tell
        """

        let result = try ShellCommand.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", appleScript],
            captureOutput: true
        )

        guard result.terminationStatus == 0 else {
            let details = [result.stderr, result.stdout]
                .first(where: { !$0.isEmpty }) ?? ""
            throw LetheScriptRunnerError.osascriptFailed(result.terminationStatus, details)
        }
    }

    public func scriptURL(for action: LetheScriptAction) -> URL {
        switch action {
        case .install:
            return paths.installScript
        case .update:
            return paths.updateScript
        case .uninstall:
            return paths.uninstallScript
        }
    }

    private func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
