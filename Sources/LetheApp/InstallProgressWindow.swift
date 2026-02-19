import AppKit
import Foundation

@MainActor
final class InstallProgressWindowController: NSWindowController {
    private let statusLabel = NSTextField(labelWithString: "Installing Lethe...")
    private let progressIndicator = NSProgressIndicator(frame: .zero)
    private let logTextView = NSTextView(frame: .zero)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private(set) var isFinished = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lethe Installation"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func append(_ message: String) {
        let text = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        logTextView.textStorage?.append(NSAttributedString(string: text))
        logTextView.scrollToEndOfDocument(nil)
    }

    func markFinished(success: Bool, summary: String) {
        guard !isFinished else {
            return
        }
        isFinished = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = success ? "Installation complete." : "Installation failed."
        append(summary)
        closeButton.isEnabled = true
        closeButton.keyEquivalent = "\r"
        window?.title = success ? "Lethe Installation Complete" : "Lethe Installation Failed"
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView(frame: .zero)
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(statusLabel)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.startAnimation(nil)
        root.addArrangedSubview(progressIndicator)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.backgroundColor = .textBackgroundColor
        scrollView.documentView = logTextView

        root.addArrangedSubview(scrollView)
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let footer = NSStackView(frame: .zero)
        footer.orientation = .horizontal
        footer.spacing = 8

        let spacer = NSView(frame: .zero)
        spacer.translatesAutoresizingMaskIntoConstraints = false

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.bezelStyle = .rounded
        closeButton.isEnabled = false

        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(closeButton)
        root.addArrangedSubview(footer)
    }

    @objc private func closePressed(_: Any?) {
        window?.close()
    }
}
