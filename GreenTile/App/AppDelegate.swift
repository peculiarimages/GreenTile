import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Key {
        static let enabled = "enabled"
        static let thirdsByDefault = "thirdsByDefault"
    }

    private let overlay = OverlayController()
    private var statusItem: NSStatusItem?
    private var trustPoll: Timer?
    private lazy var permissionWindow: PermissionWindowController = {
        let controller = PermissionWindowController()
        controller.onGranted = { [weak self] in self?.refreshStatusIcon() }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugTools.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        #endif
        UserDefaults.standard.register(defaults: [Key.enabled: true, Key.thirdsByDefault: false])
        overlay.isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        overlay.thirdsByDefault = UserDefaults.standard.bool(forKey: Key.thirdsByDefault)
        overlay.onThirdsByDefaultChange = { UserDefaults.standard.set($0, forKey: Key.thirdsByDefault) }
        overlay.start()

        buildStatusItem()

        // Without Accessibility access nothing works, so ask in every way macOS allows: the system
        // prompt, our own explanation window, and System Settings opened at the right list. Then
        // keep checking so the menu icon reflects the change as soon as it is granted.
        if !AccessibilityPermission.isGranted {
            permissionWindow.present(openSettings: true)
        }
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshStatusIcon()
        }
        refreshStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.stop()
    }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func refreshStatusIcon() {
        let active = overlay.isEnabled && AXIsProcessTrusted()
        // The capybara holding a green tile, in colour (not a template image), 18 pt square.
        let image = NSImage(named: "MenuBarIcon")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = false
        image?.accessibilityDescription = "GreenTile"
        statusItem?.button?.image = image
        statusItem?.button?.imageScaling = .scaleProportionallyDown
        statusItem?.button?.appearsDisabled = !active
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Show Tiling Buttons", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = overlay.isEnabled ? .on : .off
        menu.addItem(enabled)

        let thirds = NSMenuItem(title: "Thirds Instead of Halves", action: #selector(toggleThirds), keyEquivalent: "")
        thirds.target = self
        thirds.state = overlay.thirdsByDefault ? .on : .off
        menu.addItem(thirds)

        menu.addItem(.separator())

        if AXIsProcessTrusted() {
            let ok = NSMenuItem(title: "Accessibility Access Granted", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            let fix = NSMenuItem(title: "Grant Accessibility Access…",
                                 action: #selector(openAccessibilitySettings), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GreenTile", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    // MARK: Menu actions

    @objc private func toggleEnabled() {
        overlay.isEnabled.toggle()
        UserDefaults.standard.set(overlay.isEnabled, forKey: Key.enabled)
        refreshStatusIcon()
    }

    @objc private func toggleThirds() {
        overlay.thirdsByDefault.toggle()
    }

    @objc private func openAccessibilitySettings() {
        permissionWindow.present(openSettings: true)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("GreenTile: could not change login item: \(error.localizedDescription)")
        }
    }
}
