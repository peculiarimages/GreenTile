import AppKit
import ApplicationServices
import GreenTileKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Key {
        static let enabled = "enabled"
        static let thirdsByDefault = "thirdsByDefault"
        static let keepTilesInStageManager = "keepTilesInStageManager"
        static let keepTilesAcrossDisplays = "keepTilesAcrossDisplays"
        static let appStyles = "appStyles"
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
        UserDefaults.standard.register(defaults: [Key.enabled: true, Key.thirdsByDefault: false,
                                                  Key.keepTilesInStageManager: true,
                                                  Key.keepTilesAcrossDisplays: true])
        overlay.isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        overlay.thirdsByDefault = UserDefaults.standard.bool(forKey: Key.thirdsByDefault)
        overlay.keepsTilesInStageManager = UserDefaults.standard.bool(forKey: Key.keepTilesInStageManager)
        overlay.keepsTilesAcrossDisplays = UserDefaults.standard.bool(forKey: Key.keepTilesAcrossDisplays)
        overlay.onThirdsByDefaultChange = { UserDefaults.standard.set($0, forKey: Key.thirdsByDefault) }
        let stored = UserDefaults.standard.dictionary(forKey: Key.appStyles) as? [String: String] ?? [:]
        overlay.appStyles = stored.compactMapValues(AppOverlayStyle.init(rawValue:))
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
        // The capybara holding a green tile, in colour (not a template image), 18 pt square with rounded corners.
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

        let stage = NSMenuItem(title: "Keep Tiles in Stage Manager", action: #selector(toggleKeepTiles),
                               keyEquivalent: "")
        stage.target = self
        stage.state = overlay.keepsTilesInStageManager ? .on : .off
        stage.toolTip = "A tiled window dragged in from the Stage Manager strip goes back to the same tile"
        menu.addItem(stage)

        let displays = NSMenuItem(title: "Keep Tiles Across Displays", action: #selector(toggleKeepTilesAcrossDisplays),
                                  keyEquivalent: "")
        displays.target = self
        displays.state = overlay.keepsTilesAcrossDisplays ? .on : .off
        displays.toolTip = "A tiled window dragged onto another display takes the same tile there"
        menu.addItem(displays)

        addAppStyleItems(to: menu)

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
        let about = NSMenuItem(title: "About GreenTile", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit GreenTile", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    // MARK: Per-app settings

    /// The app in front (the menu-bar menu does not take that away) gets its three choices in the
    /// menu itself; every app with its own setting is also listed in a submenu, so it can be
    /// changed or reset without switching to it.
    private func addAppStyleItems(to menu: NSMenu) {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, let id = front.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "In \(front.localizedName ?? id):", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for item in styleItems(for: id) {
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        let listed = overlay.appStyles.keys.sorted { appName(for: $0).localizedCaseInsensitiveCompare(appName(for: $1)) == .orderedAscending }
        guard !listed.isEmpty else { return }
        let submenu = NSMenu()
        for id in listed {
            let app = NSMenuItem(title: appName(for: id), action: nil, keyEquivalent: "")
            let choices = NSMenu()
            styleItems(for: id).forEach(choices.addItem)
            app.submenu = choices
            submenu.addItem(app)
        }
        let apps = NSMenuItem(title: "Apps with Their Own Setting", action: nil, keyEquivalent: "")
        apps.submenu = submenu
        menu.addItem(apps)
    }

    private func styleItems(for bundleID: String) -> [NSMenuItem] {
        let current = overlay.appStyles[bundleID] ?? .standard
        return AppOverlayStyle.allCases.map { style in
            let item = NSMenuItem(title: style.title, action: #selector(chooseAppStyle(_:)), keyEquivalent: "")
            item.target = self
            item.state = style == current ? .on : .off
            item.representedObject = [bundleID, style.rawValue]
            return item
        }
    }

    private func appName(for bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    @objc private func chooseAppStyle(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let style = AppOverlayStyle(rawValue: pair[1]) else { return }
        // The default is not stored, so choosing it takes the app off the list.
        overlay.appStyles[pair[0]] = style == .standard ? nil : style
        UserDefaults.standard.set(overlay.appStyles.mapValues(\.rawValue), forKey: Key.appStyles)
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

    @objc private func toggleKeepTiles() {
        overlay.keepsTilesInStageManager.toggle()
        UserDefaults.standard.set(overlay.keepsTilesInStageManager, forKey: Key.keepTilesInStageManager)
    }

    /// The standard About panel (icon, name, version and copyright come from Info.plist), with a
    /// link to the project page as its credits. A menu-bar app is not active, so it is activated
    /// first or the panel would open behind other windows.
    @objc private func showAbout() {
        let link = ProjectLinks.repository
        let credits = NSMutableAttributedString(string: link, attributes: [
            .link: URL(string: link) as Any,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func toggleKeepTilesAcrossDisplays() {
        overlay.keepsTilesAcrossDisplays.toggle()
        UserDefaults.standard.set(overlay.keepsTilesAcrossDisplays, forKey: Key.keepTilesAcrossDisplays)
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
