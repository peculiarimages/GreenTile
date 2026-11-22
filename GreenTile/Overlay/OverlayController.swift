import AppKit
import ApplicationServices
import GreenTileKit

/// Keeps small tiling buttons attached below the traffic lights of every ordinary window on screen.
/// Two (left half, right half) sit under the red and green buttons; three (left, center, right
/// third) sit under red, yellow and green. Right-click picks which pair is the default and Option
/// turns it over while held. When the display a window is on has a neighbour to its left (right),
/// a chevron beside the leftmost (rightmost) button sends the window there.
///
/// How it works:
/// * The Quartz window list (cheap, no AX) is polled to follow windows as they move and restack.
///   The poll runs at 60 Hz for a second after any click, drag, app switch, Option press or Space
///   change (the moments windows get re-fronted or moved) and at about 7 Hz otherwise, which keeps
///   idle CPU low.
/// * Accessibility is consulted on a background queue, only for windows not seen before and
///   otherwise every 1.5 s, to learn where each window's traffic lights are.
/// * Each button is its own small panel ordered directly above its window, so windows in front of
///   that window also cover its buttons.
final class OverlayController {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { boost() } else { removeAllPanels() }
        }
    }

    /// Whether the buttons are thirds rather than halves while Option is not held. A right-click on
    /// any button flips it; Option turns whichever mode this picks over while it is held.
    var thirdsByDefault = false {
        didSet {
            guard thirdsByDefault != oldValue else { return }
            onThirdsByDefaultChange?(thirdsByDefault)
            boost()
        }
    }
    var onThirdsByDefaultChange: ((Bool) -> Void)?

    /// Where the controller reads the held modifier keys from. This asks the system for the
    /// current keyboard state directly, so it is right even when this app is in the background and
    /// has seen no key events. The self-test replaces it.
    var modifierFlags: () -> NSEvent.ModifierFlags = {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) ? [.option] : []
    }

    /// Lets the controller attach buttons to this app's own windows. Only the self-test sets it.
    var includesOwnWindows = false

    /// Whether to offer the chevrons that send a window to a neighbouring display. The self-tests
    /// that are about the tiling buttons switch them off to stay focused.
    var showsDisplayChevrons = true

    /// Columns 0...2 are the tiling buttons under the red, yellow and green lights; the chevrons
    /// sit one place beyond either end.
    private enum Column {
        static let leftChevron = -1
        static let rightChevron = 3
    }

    /// One button's panel: which window it belongs to and which place in the row it takes.
    private struct SlotKey: Hashable {
        let window: CGWindowID
        let column: Int
    }

    #if DEBUG
    func panelForTesting(windowNumber: Int, column: Int) -> OverlayPanel? {
        panels[SlotKey(window: CGWindowID(windowNumber), column: column)] as? OverlayPanel
    }

    func chevronPanelForTesting(windowNumber: Int, side: DisplaySide) -> ChevronPanel? {
        let column = side == .left ? Column.leftChevron : Column.rightChevron
        return panels[SlotKey(window: CGWindowID(windowNumber), column: column)] as? ChevronPanel
    }
    #endif

    /// The help bubble shown while the pointer rests on a button.
    private let help = HelpBubble()

    #if DEBUG
    var helpForTesting: ButtonHelp? { help.current }
    var helpBubbleForTesting: HelpBubble { help }
    #endif

    private var tracked: [CGWindowID: TrackedWindow] = [:]
    private var examined: Set<CGWindowID> = []
    private var panels: [SlotKey: ButtonPanel] = [:]

    private var scanInFlight = false
    private var lastScanStart: CFTimeInterval = 0
    private let scanQueue = DispatchQueue(label: "app.greentile.scan", qos: .utility)

    private var tickItem: DispatchWorkItem?
    private var fastUntil: CFTimeInterval = 0
    private var isFast = false
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    // MARK: Lifecycle

    func start() {
        guard monitors.isEmpty else { return }
        // Clicks and drags are what change window positions and stacking; follow them closely. So
        // is pressing or releasing Option, which swaps the buttons.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .flagsChanged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) { monitors.append(local) }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.boost()
            }
            observers.append((workspace, token))
        }
        scheduleTick()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        tickItem?.cancel()
        removeAllPanels()
    }

    // MARK: Polling

    private func handle(_ event: NSEvent) {
        // A click anywhere means the user is acting, not reading: take the help away. A click on the
        // bubble's own link row is the exception (it is reading, and following the link).
        if (event.type == .leftMouseDown || event.type == .rightMouseDown), !help.ownsWindow(event.window) {
            help.hide()
        }
        boost()
    }

    /// Switches to the fast poll rate for a second.
    private func boost() {
        fastUntil = CACurrentMediaTime() + 1
        if !isFast { scheduleTick() }
    }

    /// Schedules the next poll after `delay`, or after the current poll interval if none is given.
    private func scheduleTick(after delay: TimeInterval? = nil) {
        tickItem?.cancel()
        isFast = CACurrentMediaTime() < fastUntil
        let item = DispatchWorkItem { [weak self] in self?.tick() }
        tickItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? (isFast ? 1.0 / 60 : 0.15)), execute: item)
    }

    private func tick() {
        defer { scheduleTick() }
        guard isEnabled, AXIsProcessTrusted() else {
            removeAllPanels()
            return
        }

        let windows = WindowCatalog.onScreen()
        let displays = Display.all()
        let displayFrames = displays.map(\.frame)
        let primaryHeight = Display.primaryHeight

        // Halves or thirds: the right-click default, turned over while Option is held. The key
        // state is read directly, so no extra permission is involved.
        let mode = TileMode.effective(thirdsByDefault: thirdsByDefault, optionHeld: modifierFlags().contains(.option))

        // The active window: the frontmost ordinary window of the app in front. Every other window's
        // buttons are drawn half see-through, as the system dims an inactive window's controls.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let activeWindow = windows.first { $0.layer == 0 && $0.pid == frontPID }?.id

        var liveSlots = Set<SlotKey>()
        var candidates: [WindowCatalog.Info] = []
        var hasUnexamined = false

        for (index, window) in windows.enumerated() where window.layer == 0
            && (!window.isOwn || includesOwnWindows)
            && OverlayPlacement.isEligible(windowBounds: window.bounds, displayFrames: displayFrames) {
            candidates.append(window)
            if !examined.contains(window.id) { hasUnexamined = true }
            guard let info = tracked[window.id] else { continue }

            let lights = info.lightsRect.offsetBy(dx: window.bounds.minX, dy: window.bounds.minY)
            var group: [ButtonPanel] = []
            for slot in mode.slots {
                let key = SlotKey(window: window.id, column: slot.column)
                liveSlots.insert(key)
                let panel = panel(for: key, layout: slot.layout)
                panel.targetWindow = info.element
                if panel.tileButton.layout != slot.layout {
                    panel.tileButton.layout = slot.layout
                    // Option was pressed or released under a hovering pointer: update the help.
                    help.refresh(for: panel, help: ButtonHelp(for: slot.layout, thirdsByDefault: thirdsByDefault))
                }
                let frame = ScreenGeometry.flip(OverlayPlacement.frame(column: slot.column, trafficLights: lights),
                                                primaryHeight: primaryHeight)
                if panel.frame != frame { panel.setFrame(frame, display: false) }
                group.append(panel)
            }

            // Chevrons that send the window to a display beside the one it is on, shown only for
            // the sides where such a display exists.
            if showsDisplayChevrons,
               let displayIndex = ScreenGeometry.areaIndex(for: window.bounds, in: displayFrames) {
                for side in [DisplaySide.left, .right] {
                    guard let neighbour = ScreenGeometry.neighbourIndex(of: displayIndex, on: side, in: displayFrames,
                                                                        preferring: window.bounds),
                          let placed = OverlayPlacement.chevronFrame(side: side, trafficLights: lights,
                                                                     windowFrame: window.bounds)
                    else { continue }
                    let key = SlotKey(window: window.id, column: side == .left ? Column.leftChevron : Column.rightChevron)
                    liveSlots.insert(key)
                    let panel = chevronPanel(for: key, side: side)
                    panel.targetWindow = info.element
                    let name = displays[neighbour].name
                    if panel.neighbourName != name {
                        panel.neighbourName = name
                        help.refresh(for: panel, help: ButtonHelp(movingToDisplayNamed: name, side: side))
                    }
                    let frame = ScreenGeometry.flip(placed, primaryHeight: primaryHeight)
                    if panel.frame != frame { panel.setFrame(frame, display: false) }
                    group.append(panel)
                }
            }

            let muted = window.id != activeWindow
            for panel in group where panel.isMuted != muted { panel.isMuted = muted }

            // This window's panels belong in a block directly in front of it. Check the real
            // front-to-back list every time: whenever the window is brought forward (activation, a
            // click) the system moves it above its panels, and nothing else would tell us they are
            // now buried.
            let expected = Set(group.map(\.windowNumber))
            let inFront = Set(windows[max(0, index - group.count)..<index].map { Int($0.id) })
            let isStacked = group.allSatisfy(\.isVisible) && index >= group.count && inFront == expected
            if !isStacked {
                group.forEach { $0.order(.above, relativeTo: Int(window.id)) }
            }
        }

        // Drop panels of windows that went away, the middle button when Option is released, and a
        // chevron when its neighbouring display is gone or the window has moved away from it.
        for key in panels.keys where !liveSlots.contains(key) {
            if let panel = panels[key] { help.hide(ifOwnedBy: panel) }
            panels[key]?.orderOut(nil)
            panels[key] = nil
        }

        if !scanInFlight, hasUnexamined || CACurrentMediaTime() - lastScanStart > 1.5 {
            scan(candidates)
        }
    }

    // MARK: Accessibility scan

    private func scan(_ candidates: [WindowCatalog.Info]) {
        scanInFlight = true
        lastScanStart = CACurrentMediaTime()
        let previous = tracked
        scanQueue.async { [weak self] in
            let result = WindowScanner.scan(candidates, previous: previous)
            DispatchQueue.main.async {
                guard let self else { return }
                let foundNewWindows = !Set(result.tracked.keys).isSubset(of: self.tracked.keys)
                self.tracked = result.tracked
                self.examined = result.examined
                self.scanInFlight = false
                // Show buttons for newly found windows right away. An ordinary re-scan that finds
                // nothing new must not speed the poll up: that would keep the app permanently busy.
                if foundNewWindows { self.scheduleTick(after: 0.01) }
            }
        }
    }

    // MARK: Panels

    private func panel(for key: SlotKey, layout: TileLayout) -> OverlayPanel {
        if let existing = panels[key] as? OverlayPanel { return existing }
        let panel = OverlayPanel(layout: layout)
        panel.tileButton.onClick = { [weak self, weak panel] modifiers in
            guard let self, let panel, let window = panel.targetWindow else { return }
            // Judge the click by the mode in force right now (Option state included), even if the
            // buttons have not redrawn yet.
            let mode = TileMode.effective(thirdsByDefault: self.thirdsByDefault,
                                          optionHeld: modifiers.contains(.option))
            let chosen = panel.layout.adjusted(for: mode)
            // Let the click finish before the window moves.
            DispatchQueue.main.async {
                WindowActions.tile(window, chosen)
                self.boost()
            }
        }
        panel.tileButton.onSecondaryClick = { [weak self] in self?.thirdsByDefault.toggle() }
        panel.tileButton.onHoverChange = { [weak self, weak panel] hovering in
            guard let self, let panel else { return }
            if hovering {
                self.help.hoverBegan(for: panel, help: ButtonHelp(for: panel.layout, thirdsByDefault: self.thirdsByDefault))
            } else {
                self.help.hoverEnded(for: panel)
            }
        }
        panel.tileButton.onPress = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.help.hide(ifOwnedBy: panel)
        }
        panels[key] = panel
        return panel
    }

    private func chevronPanel(for key: SlotKey, side: DisplaySide) -> ChevronPanel {
        if let existing = panels[key] as? ChevronPanel { return existing }
        let panel = ChevronPanel(side: side)
        panel.chevronButton.onClick = { [weak self, weak panel] in
            guard let self, let panel, let window = panel.targetWindow else { return }
            let side = panel.side
            // Let the click finish before the window moves.
            DispatchQueue.main.async {
                WindowActions.move(window, toward: side)
                self.boost()
            }
        }
        panel.chevronButton.onHoverChange = { [weak self, weak panel] hovering in
            guard let self, let panel else { return }
            if hovering {
                self.help.hoverBegan(for: panel, help: ButtonHelp(movingToDisplayNamed: panel.neighbourName, side: panel.side))
            } else {
                self.help.hoverEnded(for: panel)
            }
        }
        panel.chevronButton.onPress = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.help.hide(ifOwnedBy: panel)
        }
        panels[key] = panel
        return panel
    }

    private func removeAllPanels() {
        help.hide()
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}
