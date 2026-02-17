import Foundation

public struct ShellCommandResult {
    public let terminationStatus: Int32
    public let stdout: String
    public let stderr: String
}

public enum ShellCommandError: Error, LocalizedError {
    case failedToLaunch(Error)

    public var errorDescription: String? {
        switch self {
        case .failedToLaunch(let error):
            return "Failed to launch command: \(error.localizedDescription)"
        }
    }
}

public enum ShellCommand {
    @discardableResult
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        captureOutput: Bool = true
    ) throws -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in
                newValue
            }
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        if captureOutput {
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
        } else {
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
        }

        do {
            try process.run()
        } catch {
            throw ShellCommandError.failedToLaunch(error)
        }

        process.waitUntilExit()

        let stdout: String
        let stderr: String

        if captureOutput {
            stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else {
            stdout = ""
            stderr = ""
        }

        return ShellCommandResult(
            terminationStatus: process.terminationStatus,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
