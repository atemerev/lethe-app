import AppKit
import Foundation
import LetheCore

struct InstallWizardDefaults {
    var provider: LetheProvider
    var anthropicAuthMode: AnthropicAuthMode
    var model: String
    var auxModel: String
    var apiBase: String
    var apiKey: String
    var telegramBotToken: String
    var telegramUserID: String
}

@MainActor
enum InstallWizard {
    private static var activeController: InstallWizardWindowController?

    static func collectConfiguration(
        defaults: InstallWizardDefaults,
        completion: @escaping (LetheInstallConfiguration?) -> Void
    ) {
        let controller = InstallWizardWindowController(defaults: defaults) { configuration in
            completion(configuration)
            activeController = nil
        }
        activeController = controller
        controller.present()
    }
}

@MainActor
private final class InstallWizardWindowController: NSWindowController, NSWindowDelegate, NSTabViewDelegate {
    private let defaults: InstallWizardDefaults
    private let completion: (LetheInstallConfiguration?) -> Void
    private var finished = false

    private let tabView = NSTabView(frame: .zero)

    private let openRouterKeyField = NSTextField(string: "")
    private let openRouterMainModelField = NSTextField(string: "")
    private let openRouterAuxModelField = NSTextField(string: "")

    private let anthropicAuthModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let anthropicCredentialLabel = NSTextField(labelWithString: "ANTHROPIC_API_KEY")
    private let anthropicCredentialField = NSTextField(string: "")
    private let anthropicMainModelField = NSTextField(string: "")
    private let anthropicAuxModelField = NSTextField(string: "")
    private let anthropicModelHintLabel = NSTextField(labelWithString: "")

    private let openAIKeyField = NSTextField(string: "")
    private let openAIMainModelField = NSTextField(string: "")
    private let openAIAuxModelField = NSTextField(string: "")

    private let telegramBotTokenField = NSTextField(string: "")
    private let telegramUserIDField = NSTextField(string: "")
    private let continueButton = NSButton(title: "Install", target: nil, action: nil)

    private let anthropicMainDefault = "claude-opus-4-6"
    private let anthropicAuxDefault = "claude-haiku-4-5-20251001"

    init(
        defaults: InstallWizardDefaults,
        completion: @escaping (LetheInstallConfiguration?) -> Void
    ) {
        self.defaults = defaults
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lethe Setup"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()

        super.init(window: window)
        window.delegate = self

        buildUI()
        populateDefaults()
        updateAnthropicAuthUI()
        setupValidationObservers()
        updateInstallButtonState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present() {
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        focusInitialField()
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        finish(result: nil)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView(frame: .zero)
        root.orientation = .vertical
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let titleLabel = NSTextField(labelWithString: "Configure Lethe")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "Select provider tab and fill configuration. You can paste normally with Cmd+V.")
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0
        root.addArrangedSubview(subtitle)

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        tabView.delegate = self
        root.addArrangedSubview(tabView)
        tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        configureTabs()

        let telegramSection = makeSection(
            title: "Telegram",
            rows: [
                makeFormRow(label: "Bot Token", control: telegramBotTokenField),
                makeFormRow(label: "User ID", control: telegramUserIDField),
            ]
        )
        root.addArrangedSubview(telegramSection)

        let buttonRow = NSStackView(frame: .zero)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView(frame: .zero)
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancelButton.bezelStyle = .rounded
        continueButton.target = self
        continueButton.action = #selector(continuePressed)
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"

        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(continueButton)
        root.addArrangedSubview(buttonRow)
    }

    private func configureTabs() {
        let openRouterItem = NSTabViewItem(identifier: LetheProvider.openrouter)
        openRouterItem.label = "OpenRouter"
        openRouterItem.view = makeOpenRouterPanel()
        tabView.addTabViewItem(openRouterItem)

        let anthropicItem = NSTabViewItem(identifier: LetheProvider.anthropic)
        anthropicItem.label = "Anthropic"
        anthropicItem.view = makeAnthropicPanel()
        tabView.addTabViewItem(anthropicItem)

        let openAIItem = NSTabViewItem(identifier: LetheProvider.openai)
        openAIItem.label = "OpenAI"
        openAIItem.view = makeOpenAIPanel()
        tabView.addTabViewItem(openAIItem)
    }

    private func makeOpenRouterPanel() -> NSView {
        makeSection(
            title: "OpenRouter Settings",
            rows: [
                makeFormRow(label: "OPENROUTER_API_KEY", control: openRouterKeyField),
                makeFormRow(label: "Main Model", control: openRouterMainModelField),
                makeFormRow(label: "Aux Model", control: openRouterAuxModelField),
            ]
        )
    }

    private func makeAnthropicPanel() -> NSView {
        anthropicAuthModePopUp.removeAllItems()
        anthropicAuthModePopUp.addItems(withTitles: ["API Key", "Subscription Token"])
        anthropicAuthModePopUp.target = self
        anthropicAuthModePopUp.action = #selector(anthropicAuthModeChanged(_:))

        anthropicModelHintLabel.lineBreakMode = .byWordWrapping
        anthropicModelHintLabel.maximumNumberOfLines = 0
        anthropicModelHintLabel.textColor = .secondaryLabelColor

        let hintContainer = NSView(frame: .zero)
        let hintStack = NSStackView(views: [anthropicModelHintLabel])
        hintStack.orientation = .vertical
        hintStack.translatesAutoresizingMaskIntoConstraints = false
        hintContainer.addSubview(hintStack)
        NSLayoutConstraint.activate([
            hintStack.leadingAnchor.constraint(equalTo: hintContainer.leadingAnchor),
            hintStack.trailingAnchor.constraint(equalTo: hintContainer.trailingAnchor),
            hintStack.topAnchor.constraint(equalTo: hintContainer.topAnchor),
            hintStack.bottomAnchor.constraint(equalTo: hintContainer.bottomAnchor),
        ])

        return makeSection(
            title: "Anthropic Settings",
            rows: [
                makeFormRow(label: "Auth Mode", control: anthropicAuthModePopUp),
                makeFormRow(labelView: anthropicCredentialLabel, control: anthropicCredentialField),
                makeFormRow(label: "Main Model", control: anthropicMainModelField),
                makeFormRow(label: "Aux Model", control: anthropicAuxModelField),
                hintContainer,
            ]
        )
    }

    private func makeOpenAIPanel() -> NSView {
        makeSection(
            title: "OpenAI Settings",
            rows: [
                makeFormRow(label: "OPENAI_API_KEY", control: openAIKeyField),
                makeFormRow(label: "Main Model", control: openAIMainModelField),
                makeFormRow(label: "Aux Model", control: openAIAuxModelField),
            ]
        )
    }

    private func makeSection(title: String, rows: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let stack = NSStackView(views: [titleLabel] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeFormRow(label: String, control: NSControl) -> NSView {
        makeFormRow(labelView: NSTextField(labelWithString: label), control: control)
    }

    private func makeFormRow(labelView: NSTextField, control: NSControl) -> NSView {
        labelView.setContentHuggingPriority(.required, for: .horizontal)

        control.translatesAutoresizingMaskIntoConstraints = false
        if let textField = control as? NSTextField {
            textField.placeholderString = ""
            textField.usesSingleLineMode = true
            textField.lineBreakMode = .byClipping
            if let cell = textField.cell as? NSTextFieldCell {
                cell.wraps = false
                cell.isScrollable = true
                cell.usesSingleLineMode = true
                cell.lineBreakMode = .byClipping
            }
        }

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline
        row.translatesAutoresizingMaskIntoConstraints = false

        labelView.widthAnchor.constraint(equalToConstant: 180).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true

        return row
    }

    private func populateDefaults() {
        openRouterMainModelField.stringValue = openRouterMainDefault()
        openRouterAuxModelField.stringValue = openRouterAuxDefault()
        openAIKeyField.stringValue = ""
        openAIMainModelField.stringValue = LetheProvider.openai.defaultModel
        openAIAuxModelField.stringValue = LetheProvider.openai.defaultAuxModel
        anthropicMainModelField.stringValue = anthropicMainDefault
        anthropicAuxModelField.stringValue = anthropicAuxDefault

        telegramBotTokenField.stringValue = defaults.telegramBotToken
        telegramUserIDField.stringValue = defaults.telegramUserID

        switch defaults.provider {
        case .openrouter:
            openRouterKeyField.stringValue = defaults.apiKey
            if !defaults.model.isEmpty { openRouterMainModelField.stringValue = defaults.model }
            if !defaults.auxModel.isEmpty { openRouterAuxModelField.stringValue = defaults.auxModel }
        case .anthropic:
            anthropicCredentialField.stringValue = defaults.apiKey
            if !defaults.model.isEmpty { anthropicMainModelField.stringValue = defaults.model }
            if !defaults.auxModel.isEmpty { anthropicAuxModelField.stringValue = defaults.auxModel }
        case .openai:
            openAIKeyField.stringValue = defaults.apiKey
            if !defaults.model.isEmpty { openAIMainModelField.stringValue = defaults.model }
            if !defaults.auxModel.isEmpty { openAIAuxModelField.stringValue = defaults.auxModel }
        }

        anthropicAuthModePopUp.selectItem(at: defaults.anthropicAuthMode == .apiKey ? 0 : 1)
        tabView.selectTabViewItem(withIdentifier: defaults.provider)
    }

    private func focusInitialField() {
        switch selectedProvider() {
        case .openrouter:
            window?.makeFirstResponder(openRouterKeyField)
        case .anthropic:
            window?.makeFirstResponder(anthropicCredentialField)
        case .openai:
            window?.makeFirstResponder(openAIKeyField)
        }
    }

    @objc private func anthropicAuthModeChanged(_ sender: NSPopUpButton) {
        _ = sender
        updateAnthropicAuthUI()
    }

    private func updateAnthropicAuthUI() {
        let authMode = selectedAnthropicAuthMode()
        if authMode == .subscriptionToken {
            anthropicCredentialLabel.stringValue = "ANTHROPIC_AUTH_TOKEN"
            anthropicMainModelField.stringValue = anthropicMainDefault
            anthropicAuxModelField.stringValue = anthropicAuxDefault
            anthropicMainModelField.isEnabled = false
            anthropicAuxModelField.isEnabled = false
            anthropicModelHintLabel.stringValue = "Subscription token mode uses fixed defaults:\nMain: \(anthropicMainDefault)\nAux: \(anthropicAuxDefault)"
        } else {
            anthropicCredentialLabel.stringValue = "ANTHROPIC_API_KEY"
            anthropicMainModelField.isEnabled = true
            anthropicAuxModelField.isEnabled = true
            anthropicModelHintLabel.stringValue = "API key mode: you can edit main and aux model values."
        }
        updateInstallButtonState()
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        _ = tabView
        _ = tabViewItem
        updateInstallButtonState()
    }

    private func setupValidationObservers() {
        let fields = [
            openRouterKeyField,
            openRouterMainModelField,
            openRouterAuxModelField,
            anthropicCredentialField,
            anthropicMainModelField,
            anthropicAuxModelField,
            openAIKeyField,
            openAIMainModelField,
            openAIAuxModelField,
            telegramBotTokenField,
            telegramUserIDField,
        ]
        for field in fields {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(textFieldChanged(_:)),
                name: NSControl.textDidChangeNotification,
                object: field
            )
        }
    }

    @objc private func textFieldChanged(_ notification: Notification) {
        _ = notification
        updateInstallButtonState()
    }

    private func updateInstallButtonState() {
        continueButton.isEnabled = isConfigurationInputComplete()
    }

    private func isConfigurationInputComplete() -> Bool {
        func trimmed(_ field: NSTextField) -> String {
            field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed(telegramBotTokenField).isEmpty else { return false }
        guard !trimmed(telegramUserIDField).isEmpty else { return false }

        switch selectedProvider() {
        case .openrouter:
            return !trimmed(openRouterKeyField).isEmpty
                && !trimmed(openRouterMainModelField).isEmpty
                && !trimmed(openRouterAuxModelField).isEmpty
        case .anthropic:
            guard !trimmed(anthropicCredentialField).isEmpty else { return false }
            if selectedAnthropicAuthMode() == .subscriptionToken {
                return true
            }
            return !trimmed(anthropicMainModelField).isEmpty
                && !trimmed(anthropicAuxModelField).isEmpty
        case .openai:
            return !trimmed(openAIKeyField).isEmpty
                && !trimmed(openAIMainModelField).isEmpty
                && !trimmed(openAIAuxModelField).isEmpty
        }
    }

    @objc private func continuePressed(_: Any?) {
        guard let config = buildConfiguration() else {
            return
        }

        finish(result: config)
    }

    @objc private func cancelPressed(_: Any?) {
        finish(result: nil)
    }

    private func finish(result: LetheInstallConfiguration?) {
        guard !finished else {
            return
        }
        finished = true

        if let window, window.isVisible {
            window.orderOut(nil)
            window.close()
        }

        completion(result)
    }

    private func buildConfiguration() -> LetheInstallConfiguration? {
        window?.endEditing(for: nil)

        let provider = selectedProvider()
        let telegramBotToken = telegramBotTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let telegramUserID = telegramUserIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !telegramBotToken.isEmpty else {
            showValidationError("Telegram Bot Token is required.", focus: telegramBotTokenField)
            return nil
        }
        guard !telegramUserID.isEmpty else {
            showValidationError("Telegram User ID is required.", focus: telegramUserIDField)
            return nil
        }

        let apiBase = defaults.apiBase.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openrouter:
            let apiKey = openRouterKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let mainModel = openRouterMainModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let auxModel = openRouterAuxModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !apiKey.isEmpty else {
                showValidationError("OPENROUTER_API_KEY is required.", focus: openRouterKeyField)
                return nil
            }
            guard !mainModel.isEmpty else {
                showValidationError("OpenRouter main model is required.", focus: openRouterMainModelField)
                return nil
            }
            guard !auxModel.isEmpty else {
                showValidationError("OpenRouter aux model is required.", focus: openRouterAuxModelField)
                return nil
            }

            return LetheInstallConfiguration(
                provider: .openrouter,
                anthropicAuthMode: .apiKey,
                model: mainModel,
                auxModel: auxModel,
                apiBase: apiBase,
                apiKey: apiKey,
                telegramBotToken: telegramBotToken,
                telegramUserID: telegramUserID
            )

        case .anthropic:
            let authMode = selectedAnthropicAuthMode()
            let apiKey = anthropicCredentialField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                showValidationError("\(authMode == .apiKey ? "ANTHROPIC_API_KEY" : "ANTHROPIC_AUTH_TOKEN") is required.", focus: anthropicCredentialField)
                return nil
            }

            let mainModel: String
            let auxModel: String
            if authMode == .subscriptionToken {
                mainModel = anthropicMainDefault
                auxModel = anthropicAuxDefault
            } else {
                mainModel = anthropicMainModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                auxModel = anthropicAuxModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !mainModel.isEmpty else {
                    showValidationError("Anthropic main model is required.", focus: anthropicMainModelField)
                    return nil
                }
                guard !auxModel.isEmpty else {
                    showValidationError("Anthropic aux model is required.", focus: anthropicAuxModelField)
                    return nil
                }
            }

            return LetheInstallConfiguration(
                provider: .anthropic,
                anthropicAuthMode: authMode,
                model: mainModel,
                auxModel: auxModel,
                apiBase: apiBase,
                apiKey: apiKey,
                telegramBotToken: telegramBotToken,
                telegramUserID: telegramUserID
            )

        case .openai:
            let apiKey = openAIKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let mainModel = openAIMainModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let auxModel = openAIAuxModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !apiKey.isEmpty else {
                showValidationError("OPENAI_API_KEY is required.", focus: openAIKeyField)
                return nil
            }
            guard !mainModel.isEmpty else {
                showValidationError("OpenAI main model is required.", focus: openAIMainModelField)
                return nil
            }
            guard !auxModel.isEmpty else {
                showValidationError("OpenAI aux model is required.", focus: openAIAuxModelField)
                return nil
            }

            return LetheInstallConfiguration(
                provider: .openai,
                anthropicAuthMode: .apiKey,
                model: mainModel,
                auxModel: auxModel,
                apiBase: apiBase,
                apiKey: apiKey,
                telegramBotToken: telegramBotToken,
                telegramUserID: telegramUserID
            )
        }
    }

    private func showValidationError(_ message: String, focus: NSView) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Validation Error"
        alert.informativeText = message
        alert.runModal()
        window?.makeFirstResponder(focus)
    }

    private func selectedProvider() -> LetheProvider {
        if let provider = tabView.selectedTabViewItem?.identifier as? LetheProvider {
            return provider
        }
        return .openrouter
    }

    private func selectedAnthropicAuthMode() -> AnthropicAuthMode {
        anthropicAuthModePopUp.indexOfSelectedItem == 1 ? .subscriptionToken : .apiKey
    }

    private func openRouterMainDefault() -> String {
        LetheProvider.openrouter.defaultModel
    }

    private func openRouterAuxDefault() -> String {
        "openrouter/google/gemini-3-flash-preview"
    }
}
