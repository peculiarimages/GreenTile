import AppKit

/// A small window that walks the user through switching on Accessibility access. It stays up until
/// the permission is granted (or the user chooses Later), checks every second, and closes itself
/// once GreenTile is trusted.
final class PermissionWindowController: NSWindowController, NSWindowDelegate {
    var onGranted: (() -> Void)?

    private var poll: Timer?
    private let status = NSTextField(labelWithString: "")

    init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "GreenTile needs Accessibility access"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the window, asks macOS for its own prompt and opens the Accessibility settings.
    func present(openSettings: Bool) {
        refreshStatus()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        AccessibilityPermission.askSystem()
        if openSettings {
            // Give the system prompt a moment so Settings doesn't open on top of it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { AccessibilityPermission.openSettings() }
        }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        guard AccessibilityPermission.isGranted else { return }
        poll?.invalidate()
        poll = nil
        status.stringValue = "Thanks! GreenTile is ready. The buttons will appear under your windows."
        status.textColor = .systemGreen
        onGranted?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
    }

    private func refreshStatus() {
        if AccessibilityPermission.isTranslocated {
            status.stringValue = "GreenTile is running from Downloads. Quit it, move GreenTile.app to your Applications folder, and open it from there, or the permission won't stick."
            status.textColor = .systemOrange
        } else {
            status.stringValue = "Waiting for access…"
            status.textColor = .secondaryLabelColor
        }
    }

    // MARK: Layout

    private func buildContent() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let headline = NSTextField(labelWithString: "Allow GreenTile to move and resize windows")
        headline.font = .boldSystemFont(ofSize: 14)

        let body = NSTextField(wrappingLabelWithString: """
        GreenTile uses Accessibility to find each window's traffic lights and to tile the window. \
        Until it is allowed, no buttons appear.

        1. In System Settings, open Privacy & Security > Accessibility.
        2. Switch on GreenTile. If it isn't in the list, click + and choose GreenTile from Applications.
        3. If GreenTile is already switched on but this window stays, click Ask Again.
        """)
        body.preferredMaxLayoutWidth = 360

        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 0
        status.preferredMaxLayoutWidth = 360

        let open = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        open.keyEquivalent = "\r"
        let again = NSButton(title: "Ask Again", target: self, action: #selector(askAgain))
        again.toolTip = "Removes GreenTile's entry from the Accessibility list so macOS asks again"
        let later = NSButton(title: "Later", target: self, action: #selector(later))
        later.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [later, again, open])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let text = NSStackView(views: [headline, body, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 10
        text.translatesAutoresizingMaskIntoConstraints = false
        text.widthAnchor.constraint(equalToConstant: 360).isActive = true
        for label in [body, status] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }

        let top = NSStackView(views: [icon, text])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 16

        let root = NSStackView(views: [top, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window?.contentView = content
        window?.setContentSize(content.fittingSize)
        refreshStatus()
    }

    @objc private func openSettings() { AccessibilityPermission.openSettings() }

    @objc private func askAgain() {
        AccessibilityPermission.resetAndAsk()
        refreshStatus()
    }

    @objc private func later() { close() }
}
