import AppKit
import Foundation
import LetheCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let paths = LethePaths()
    private let serviceController = LetheServiceController()
    private let statusProbe = LetheStatusProbe()
    private let nativeInstaller = LetheNativeInstaller()

    private let startMenuItem = NSMenuItem(title: "Start", action: #selector(startService), keyEquivalent: "s")
    private let stopMenuItem = NSMenuItem(title: "Stop", action: #selector(stopService), keyEquivalent: "t")
    private let uninstallMenuItem = NSMenuItem(title: "Uninstall", action: #selector(uninstallNative), keyEquivalent: "u")
    private var initialOnboardingChecked = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusBar()
        refreshStatus()
        startInitialOnboardingIfNeeded()
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
        if let button = statusItem.button {
            button.title = "Lethe"
        }

        let menu = NSMenu()
        startMenuItem.target = self
        stopMenuItem.target = self
        uninstallMenuItem.target = self

        menu.addItem(startMenuItem)
        menu.addItem(stopMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(uninstallMenuItem)

        statusItem.menu = menu
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

    private func runServiceAction(_ title: String, action: () throws -> Void) {
        do {
            try action()
            refreshStatus()
        } catch {
            showError(title: title, error: error)
        }
    }

    @objc private func refreshStatus() {
        let status = statusProbe.currentStatus()
        let installedAndManaged = status.installed && status.launchAgentInstalled

        startMenuItem.isEnabled = installedAndManaged && !status.launchAgentLoaded
        stopMenuItem.isEnabled = installedAndManaged && status.launchAgentLoaded
        uninstallMenuItem.isEnabled = status.installed

        if installedAndManaged {
            if status.launchAgentLoaded {
                startMenuItem.state = .off
                stopMenuItem.state = .on
            } else {
                startMenuItem.state = .on
                stopMenuItem.state = .off
            }
        } else {
            startMenuItem.state = .off
            stopMenuItem.state = .off
        }
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
            self?.configureAndInstallNative()
        }
    }

    private func configureAndInstallNative() {
        let defaults = installDefaultsFromExistingConfig()
        InstallWizard.collectConfiguration(defaults: defaults) { [weak self] configuration in
            guard
                let self,
                let configuration
            else {
                return
            }

            showInfo(
                title: "Install Started",
                message: "Installing Lethe in the background. This can take a few minutes."
            )

            DispatchQueue.global(qos: .userInitiated).async { [nativeInstaller] in
                do {
                    let result = try nativeInstaller.install(config: configuration)
                    DispatchQueue.main.async { [weak self] in
                        self?.refreshStatus()
                        self?.showInfo(
                            title: "Install Complete",
                            message: """
                            Lethe is installed.

                            Install dir: \(result.installDirectory.path)
                            Config: \(result.configFile.path)
                            LaunchAgent: \(result.launchAgent.path)
                            """
                        )
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.showError(title: "Install Failed", error: error)
                    }
                }
            }
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
            if values["ANTHROPIC_API_KEY"] != nil {
                return .apiKey
            }
            return .subscriptionToken
        }()

        return InstallWizardDefaults(
            provider: provider,
            anthropicAuthMode: anthropicAuthMode,
            model: values["LLM_MODEL"] ?? provider.defaultModel,
            auxModel: values["LLM_MODEL_AUX"] ?? provider.defaultAuxModel,
            apiBase: values["LLM_API_BASE"] ?? "",
            apiKey: values["OPENROUTER_API_KEY"]
                ?? values["ANTHROPIC_API_KEY"]
                ?? values["ANTHROPIC_AUTH_TOKEN"]
                ?? values["OPENAI_API_KEY"]
                ?? "",
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
