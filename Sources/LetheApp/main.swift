import AppKit
import Foundation
import LetheCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum StatusIconBadge {
        case none
        case active
        case installing
    }

    private enum StatusIconAppearance {
        case notInstalled
        case stopped
        case running
        case installing

        var silhouetteAlpha: CGFloat {
            switch self {
            case .notInstalled:
                return 0.6
            case .stopped:
                return 0.78
            case .running:
                return 1.0
            case .installing:
                return 1.0
            }
        }

        var badge: StatusIconBadge {
            switch self {
            case .running:
                return .active
            case .installing:
                return .installing
            case .notInstalled, .stopped:
                return .none
            }
        }

        var toolTip: String {
            switch self {
            case .notInstalled:
                return "Lethe (Not Installed)"
            case .stopped:
                return "Lethe (Stopped)"
            case .running:
                return "Lethe (Running)"
            case .installing:
                return "Lethe (Installing)"
            }
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let paths = LethePaths()
    private let serviceController = LetheServiceController()
    private let statusProbe = LetheStatusProbe()
    private let nativeInstaller = LetheNativeInstaller()
    private let fileManager = FileManager.default

    private let startMenuItem = NSMenuItem(title: "Start", action: #selector(startService), keyEquivalent: "s")
    private let stopMenuItem = NSMenuItem(title: "Stop", action: #selector(stopService), keyEquivalent: "t")
    private let showWebConsoleMenuItem = NSMenuItem(title: "Show Web Console", action: #selector(showWebConsole), keyEquivalent: "w")
    private let showInstallLogMenuItem = NSMenuItem(title: "Show Install Log", action: #selector(showInstallLog), keyEquivalent: "l")
    private let openRuntimeLogsMenuItem = NSMenuItem(title: "Open Runtime Logs", action: #selector(openRuntimeLogs), keyEquivalent: "r")
    private let uninstallMenuItem = NSMenuItem(title: "Uninstall", action: #selector(uninstallNative), keyEquivalent: "u")
    private let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    private var initialOnboardingChecked = false
    private var isInstalling = false
    private var installProgressWindow: InstallProgressWindowController?
    private var statusRefreshTimer: Timer?
    private var rapidStatusRefreshTimer: Timer?
    private var rapidStatusRefreshTicksRemaining = 0
    private let installLogTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private var installLogPath: URL {
        paths.configDirectory.appending(path: "installer.log", directoryHint: .notDirectory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setDockIconVisible(false)
        setupMainMenu()
        setupStatusBar()
        refreshStatus()
        startStatusRefreshTimer()
        startInitialOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = nil
        rapidStatusRefreshTimer?.invalidate()
        rapidStatusRefreshTimer = nil
    }

    private func setDockIconVisible(_ visible: Bool) {
        let targetPolicy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }

    private func startStatusRefreshTimer() {
        statusRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        statusRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startRapidStatusRefresh(
        interval: TimeInterval = 0.25,
        ticks: Int = 12
    ) {
        rapidStatusRefreshTimer?.invalidate()
        rapidStatusRefreshTicksRemaining = ticks
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleRapidStatusRefreshTick(_:)),
            userInfo: nil,
            repeats: true
        )
        rapidStatusRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func handleRapidStatusRefreshTick(_ timer: Timer) {
        refreshStatus()
        rapidStatusRefreshTicksRemaining -= 1
        if rapidStatusRefreshTicksRemaining <= 0 {
            timer.invalidate()
            rapidStatusRefreshTimer = nil
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu(title: "")

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = buildAppMenu()

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = buildEditMenu()

        NSApp.mainMenu = mainMenu
    }

    private func buildAppMenu() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: appName)

        menu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = nil
        menu.addItem(quitItem)

        return menu
    }

    private func buildEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil
        menu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.target = nil
        menu.addItem(selectAllItem)

        return menu
    }

    private func setupStatusBar() {
        applyStatusItemAppearance(.notInstalled)

        let menu = NSMenu()
        menu.delegate = self
        startMenuItem.target = self
        stopMenuItem.target = self
        showWebConsoleMenuItem.target = self
        showInstallLogMenuItem.target = self
        openRuntimeLogsMenuItem.target = self
        uninstallMenuItem.target = self
        quitMenuItem.target = self
        startMenuItem.state = .off
        stopMenuItem.state = .off

        menu.addItem(startMenuItem)
        menu.addItem(stopMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(showWebConsoleMenuItem)
        menu.addItem(showInstallLogMenuItem)
        menu.addItem(openRuntimeLogsMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(uninstallMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        _ = menu
        refreshStatus()
        startRapidStatusRefresh(interval: 0.2, ticks: 10)
    }

    func menuDidClose(_ menu: NSMenu) {
        _ = menu
        rapidStatusRefreshTimer?.invalidate()
        rapidStatusRefreshTimer = nil
    }

    @objc private func uninstallNative() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Lethe"
        alert.informativeText = "This removes ~/.lethe and the launch agent. Config in ~/.config/lethe is kept."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [nativeInstaller] in
            do {
                try nativeInstaller.uninstall()
                DispatchQueue.main.async { [weak self] in
                    self?.refreshStatus()
                    self?.showInfo(title: "Uninstall Complete", message: "Lethe has been removed.")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showError(title: "Uninstall Failed", error: error)
                }
            }
        }
    }

    @objc private func startService() {
        runServiceAction("Start") { _ = try serviceController.start() }
    }

    @objc private func stopService() {
        runServiceAction("Stop") { _ = try serviceController.stop() }
    }

    @objc private func showWebConsole() {
        let console = currentConsoleConfiguration()
        guard console.enabled else {
            showInfo(
                title: "Web Console Disabled",
                message: "Set LETHE_CONSOLE=true in ~/.config/lethe/.env and restart Lethe."
            )
            return
        }
        guard let url = URL(string: "http://127.0.0.1:\(console.port)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showInstallLog() {
        let logPath = installLogPath.path
        guard fileManager.fileExists(atPath: logPath) else {
            showInfo(title: "Install Log", message: "Install log is not available yet.")
            return
        }
        NSWorkspace.shared.open(installLogPath)
    }

    @objc private func openRuntimeLogs() {
        let runtimeLogs = [paths.launchdStdoutLogPath, paths.launchdStderrLogPath]
        var openedAny = false
        for logURL in runtimeLogs where fileManager.fileExists(atPath: logURL.path) {
            openedAny = true
            NSWorkspace.shared.open(logURL)
        }
        if !openedAny {
            NSWorkspace.shared.open(paths.launchdStdoutLogPath.deletingLastPathComponent())
            showInfo(
                title: "Runtime Logs",
                message: "No runtime logs yet. Opened ~/Library/Logs."
            )
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func runServiceAction(_ title: String, action: () throws -> Void) {
        do {
            try action()
            refreshStatus()
            startRapidStatusRefresh()
        } catch {
            showError(title: title, error: error)
        }
    }

    @objc private func refreshStatus() {
        if isInstalling {
            applyStatusItemAppearance(.installing)
            startMenuItem.isEnabled = false
            stopMenuItem.isEnabled = false
            showWebConsoleMenuItem.isEnabled = false
            uninstallMenuItem.isEnabled = false
            showInstallLogMenuItem.isEnabled = true
            openRuntimeLogsMenuItem.isEnabled = true
            startMenuItem.state = .off
            stopMenuItem.state = .off
            return
        }

        let status = statusProbe.currentStatus()
        let installedAndManaged = status.installed && status.launchAgentInstalled
        let running = status.launchAgentRunning
        let active = status.launchAgentLoaded || running
        let console = currentConsoleConfiguration()

        if !status.installed {
            applyStatusItemAppearance(.notInstalled)
        } else if active {
            applyStatusItemAppearance(.running)
        } else {
            applyStatusItemAppearance(.stopped)
        }

        startMenuItem.isEnabled = installedAndManaged && !active
        stopMenuItem.isEnabled = installedAndManaged && active
        showWebConsoleMenuItem.isEnabled = installedAndManaged && active && console.enabled
        uninstallMenuItem.isEnabled = status.installed
        showInstallLogMenuItem.isEnabled = fileManager.fileExists(atPath: installLogPath.path)
        openRuntimeLogsMenuItem.isEnabled = true
        startMenuItem.state = .off
        stopMenuItem.state = .off
    }

    private func startInitialOnboardingIfNeeded() {
        guard !initialOnboardingChecked else {
            return
        }
        initialOnboardingChecked = true

        let status = statusProbe.currentStatus()
        guard !status.installed else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.setDockIconVisible(true)
            self?.configureAndInstallNative()
        }
    }

    private func configureAndInstallNative() {
        let defaults = installDefaultsFromExistingConfig()
        InstallWizard.collectConfiguration(defaults: defaults) { [weak self] configuration in
            guard let self else {
                return
            }
            guard let configuration else {
                self.appendInstallLog("Installation canceled by user. Quitting app.")
                NSApp.terminate(nil)
                return
            }

            let progressWindow = InstallProgressWindowController()
            self.installProgressWindow = progressWindow
            self.isInstalling = true
            self.refreshStatus()

            progressWindow.present()
            progressWindow.append("Starting installation.")
            self.appendInstallLog("Starting installation.")

            DispatchQueue.global(qos: .userInitiated).async { [nativeInstaller] in
                do {
                    let result = try nativeInstaller.install(config: configuration) { message in
                        DispatchQueue.main.async { [weak self] in
                            self?.installProgressWindow?.append(message)
                            self?.appendInstallLog(message)
                        }
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else {
                            return
                        }
                        self.isInstalling = false
                        self.refreshStatus()
                        let summary = """
                            Lethe is installed.
                            Install dir: \(result.installDirectory.path)
                            Config: \(result.configFile.path)
                            LaunchAgent: \(result.launchAgent.path)
                            """
                        self.installProgressWindow?.markFinished(
                            success: true,
                            summary: summary
                        )
                        self.appendInstallLog("Installation finished successfully.")
                        self.appendInstallLog(summary.replacingOccurrences(of: "\n", with: " "))

                        var startStatusMessage = "Lethe service has been started."
                        do {
                            _ = try self.serviceController.start()
                            self.refreshStatus()
                            self.appendInstallLog("Confirmed service is started.")
                        } catch {
                            startStatusMessage = "Lethe is installed, but auto-start failed: \(error.localizedDescription)"
                            self.appendInstallLog(startStatusMessage)
                        }

                        let botID = configuration.telegramBotToken
                            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                            .first
                            .map(String.init) ?? "unknown"
                        let finalMessage = """
                            Installation completed successfully.

                            \(startStatusMessage)

                            Next step:
                            Open Telegram and say "hi" in the chat with your configured bot.
                            Bot ID: \(botID)
                            Allowed User ID: \(configuration.telegramUserID)
                            """

                        self.installProgressWindow?.window?.close()
                        NSApp.activate(ignoringOtherApps: true)
                        self.showInfo(title: "Lethe Is Ready", message: finalMessage)
                        self.setDockIconVisible(false)
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.isInstalling = false
                        self?.setDockIconVisible(false)
                        self?.refreshStatus()
                        self?.appendInstallLog("Installation failed: \(error.localizedDescription)")
                        self?.installProgressWindow?.markFinished(
                            success: false,
                            summary: "Error: \(error.localizedDescription)"
                        )
                        self?.installProgressWindow?.present()
                    }
                }
            }
        }
    }

    private func appendInstallLog(_ message: String) {
        let entry = "[\(installLogTimestampFormatter.string(from: Date()))] \(message)\n"
        do {
            try fileManager.createDirectory(
                at: paths.configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            if !fileManager.fileExists(atPath: installLogPath.path) {
                fileManager.createFile(atPath: installLogPath.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: installLogPath)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(entry.utf8))
        } catch {
            // Best effort only.
        }
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func installDefaultsFromExistingConfig() -> InstallWizardDefaults {
        let values = parseEnvFile(at: paths.configDirectory.appending(path: ".env", directoryHint: .notDirectory))

        let provider = LetheProvider(rawValue: values["LLM_PROVIDER"] ?? "") ?? .openrouter
        let anthropicAuthMode: AnthropicAuthMode = {
            if provider == .anthropic {
                let hasApiKey = !(values["ANTHROPIC_API_KEY"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                return hasApiKey ? .apiKey : .subscriptionToken
            }
            return .apiKey
        }()

        func firstNonEmpty(_ candidates: [String?]) -> String {
            for candidate in candidates {
                let value = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
            return ""
        }

        let providerAPIKey: String = {
            switch provider {
            case .openrouter:
                return firstNonEmpty([values["OPENROUTER_API_KEY"]])
            case .anthropic:
                if anthropicAuthMode == .apiKey {
                    return firstNonEmpty([values["ANTHROPIC_API_KEY"]])
                }
                return firstNonEmpty([values["ANTHROPIC_AUTH_TOKEN"]])
            case .openai:
                return firstNonEmpty([values["OPENAI_API_KEY"]])
            }
        }()

        let fallbackAPIKey = firstNonEmpty([
            values["OPENROUTER_API_KEY"],
            values["ANTHROPIC_API_KEY"],
            values["ANTHROPIC_AUTH_TOKEN"],
            values["OPENAI_API_KEY"],
        ])

        return InstallWizardDefaults(
            provider: provider,
            anthropicAuthMode: anthropicAuthMode,
            model: values["LLM_MODEL"] ?? provider.defaultModel,
            auxModel: values["LLM_MODEL_AUX"] ?? provider.defaultAuxModel,
            apiBase: values["LLM_API_BASE"] ?? "",
            apiKey: providerAPIKey.isEmpty ? fallbackAPIKey : providerAPIKey,
            telegramBotToken: values["TELEGRAM_BOT_TOKEN"] ?? "",
            telegramUserID: values["TELEGRAM_ALLOWED_USER_IDS"] ?? ""
        )
    }

    private func parseEnvFile(at url: URL) -> [String: String] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        var map: [String: String] = [:]
        for line in data.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            guard let idx = trimmed.firstIndex(of: "=") else {
                continue
            }
            let key = String(trimmed[..<idx])
            let value = String(trimmed[trimmed.index(after: idx)...])
            map[key] = value
        }
        return map
    }

    private func currentConsoleConfiguration() -> (enabled: Bool, port: Int) {
        let values = parseEnvFile(at: paths.configDirectory.appending(path: ".env", directoryHint: .notDirectory))
        let enabledValue = (values["LETHE_CONSOLE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let enabled = enabledValue == "true" || enabledValue == "1" || enabledValue == "yes"
        let port = Int(values["LETHE_CONSOLE_PORT"] ?? "") ?? 8777
        return (enabled, port)
    }

    private func applyStatusItemAppearance(_ appearance: StatusIconAppearance) {
        guard let button = statusItem.button else {
            return
        }

        let icon = makeSilhouetteStatusIcon(
            alpha: appearance.silhouetteAlpha,
            badge: appearance.badge
        )
        button.title = ""
        button.image = icon
        button.alternateImage = icon
        button.imagePosition = .imageOnly
        button.contentTintColor = nil

        if icon.size.width <= 0 || icon.size.height <= 0 {
            button.image = nil
            button.alternateImage = nil
            button.contentTintColor = nil
            button.title = "L"
        }
        button.toolTip = appearance.toolTip
    }

    private func makeSilhouetteStatusIcon(alpha: CGFloat, badge: StatusIconBadge) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        bounds.fill()

        drawCalligraphicL(in: bounds, alpha: alpha, badge: badge)
        drawStatusBadge(badge, in: bounds)
        image.isTemplate = false
        return image
    }

    private func drawCalligraphicL(in rect: NSRect, alpha: CGFloat, badge: StatusIconBadge) {
        let glyph = "ℒ"
        let fontSize: CGFloat = {
            switch badge {
            case .none:
                return 15.2
            case .active, .installing:
                return 15.6
            }
        }()
        let fontNames = [
            "TimesNewRomanPSMT",
            "Baskerville",
            "Georgia",
            "HelveticaNeue",
            "AvenirNext-Regular",
        ]
        var font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        for name in fontNames {
            if let candidate = NSFont(name: name, size: fontSize) {
                font = candidate
                break
            }
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: alpha),
        ]
        let attributed = NSAttributedString(string: glyph, attributes: attributes)
        let textSize = attributed.size()
        let drawRect = NSRect(
            x: rect.midX - (textSize.width / 2.0),
            y: rect.midY - (textSize.height / 2.0) - 0.4,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: drawRect)
    }

    private func drawStatusBadge(_ badge: StatusIconBadge, in rect: NSRect) {
        let scale = min(rect.width, rect.height) / 16.0
        let x: (CGFloat) -> CGFloat = { rect.minX + ($0 * scale) }
        let y: (CGFloat) -> CGFloat = { rect.minY + ($0 * scale) }
        let s: (CGFloat) -> CGFloat = { $0 * scale }

        switch badge {
        case .none:
            return
        case .active:
            NSColor.white.setFill()
            let sparkle = NSBezierPath()
            sparkle.move(to: NSPoint(x: x(13.2), y: y(4.8)))
            sparkle.line(to: NSPoint(x: x(14.2), y: y(3.8)))
            sparkle.line(to: NSPoint(x: x(13.2), y: y(2.8)))
            sparkle.line(to: NSPoint(x: x(12.2), y: y(3.8)))
            sparkle.close()
            sparkle.fill()
        case .installing:
            NSColor.white.setFill()
            for offset in [0.0, 1.2, 2.4] {
                NSBezierPath(ovalIn: NSRect(x: x(11.7 + offset), y: y(2.6), width: s(0.8), height: s(0.8))).fill()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
