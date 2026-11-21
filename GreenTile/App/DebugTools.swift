#if DEBUG
import AppKit
import ApplicationServices
import GreenTileKit

/// Developer switches (Debug builds only). Each runs once and exits. Start the ones that need
/// Accessibility with `open -n GreenTile.app --args <switch> <path>` so the app itself (not the
/// terminal) is the process that needs the permission.
///
/// * `--render-overlay <dir>`: writes overlay-<mode>-light/dark.png, the buttons drawn under mock
///   traffic lights (halves and thirds). Needs no permissions.
/// * `--dump-windows <file>`: what the Accessibility scan finds for every window on screen, and
///   where each button would go.
/// * `--selftest-tile <file>`: tiles a throwaway window to every layout on every display.
/// * `--selftest-stacking <file>`: re-fronts a throwaway window and checks its buttons stay in front.
/// * `--selftest-help <file>`: hovers buttons with synthetic events; checks the help bubble's timing,
///   text, placement and dismissal.
/// * `--selftest-modes <file>`: fakes the Option key; checks the halves/thirds swap, that each button
///   sits under its traffic light, and what every button does.
enum DebugTools {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        func path(after flag: String) -> URL? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return URL(fileURLWithPath: args[i + 1])
        }
        if let url = path(after: "--render-overlay") { renderOverlay(into: url); return true }
        if let url = path(after: "--dump-windows") { dumpWindows(to: url); return true }
        if let url = path(after: "--selftest-tile") { selfTestTile(report: url); return true }
        if let url = path(after: "--selftest-stacking") { selfTestStacking(report: url); return true }
        if let url = path(after: "--selftest-modes") { selfTestModes(report: url); return true }
        if let url = path(after: "--selftest-help") { selfTestHelp(report: url); return true }
        return false
    }

    // MARK: Helpers

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)), \(Int(r.minY)), \(Int(r.width))x\(Int(r.height)))"
    }

    private static func makeTestWindow(title: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 300, y: 500, width: 700, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Frames (Accessibility coordinates) of the button panels stacked directly above `window`,
    /// i.e. the unbroken run of this app's own windows immediately in front of it.
    private static func panelFramesAbove(_ window: NSWindow) -> [CGRect] {
        let list = WindowCatalog.onScreen()
        guard let index = list.firstIndex(where: { Int($0.id) == window.windowNumber }) else { return [] }
        var frames: [CGRect] = []
        var i = index - 1
        while i >= 0, list[i].isOwn {
            frames.append(list[i].bounds)
            i -= 1
        }
        return frames.sorted { $0.minX < $1.minX }
    }

    /// The test window's real traffic lights, measured through Accessibility.
    private static func trafficLights(of ax: AXUIElement) -> CGRect? {
        guard let zoom = AX.zoomButton(of: ax).flatMap({ AX.frame(of: $0) }) else { return nil }
        let close = AX.element(ax, kAXCloseButtonAttribute).flatMap { AX.frame(of: $0) }
        return close.map { $0.union(zoom) } ?? zoom
    }

    private static func ownStandardWindow() -> AXUIElement? {
        AX.elements(AXUIElementCreateApplication(getpid()), kAXWindowsAttribute)
            .first { AX.string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
    }

    // MARK: Help bubble self-test

    private static func selfTestHelp(report file: URL) {
        var report = "AX trusted: \(AXIsProcessTrusted())\n"
        var failures = 0
        func record(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            report += "\(label): \(ok ? "OK" : "FAIL") \(detail)\n"
        }

        var held: NSEvent.ModifierFlags = []
        let controller = OverlayController()
        controller.includesOwnWindows = true
        controller.modifierFlags = { held }
        controller.start()
        let window = makeTestWindow(title: "GreenTile help test")
        pump(2.0)

        func finish() {
            report += failures == 0 ? "ALL PASSED\n" : "\(failures) FAILED\n"
            controller.stop()
            window.close()
            try? report.write(to: file, atomically: true, encoding: .utf8)
        }
        func button(_ column: Int) -> (panel: OverlayPanel, button: TileButton)? {
            controller.panelForTesting(windowNumber: window.windowNumber, column: column).map { ($0, $0.tileButton) }
        }
        func hover(_ type: NSEvent.EventType, _ target: (panel: OverlayPanel, button: TileButton)) {
            let event = NSEvent.enterExitEvent(with: type, location: NSPoint(x: 8, y: 8), modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: target.panel.windowNumber, context: nil,
                                               eventNumber: 0, trackingNumber: 0, userData: nil)
            if let event {
                type == .mouseEntered ? target.button.mouseEntered(with: event) : target.button.mouseExited(with: event)
            }
        }
        func bubbleFrame() -> CGRect? {
            WindowCatalog.onScreen().first { Int($0.id) == controller.helpWindowNumberForTesting }?.bounds
        }
        func shows(_ layout: TileLayout, thirdsByDefault: Bool = false) -> Bool {
            controller.helpForTesting == ButtonHelp(for: layout, thirdsByDefault: thirdsByDefault) && bubbleFrame() != nil
        }

        guard let left = button(0) else {
            record("find the buttons", false)
            finish(); return
        }
        record("no bubble before hovering", bubbleFrame() == nil && controller.helpForTesting == nil)

        // Timing: nothing straight away, the bubble after the pause.
        hover(.mouseEntered, left)
        pump(0.2)
        record("no bubble before the pause is up", bubbleFrame() == nil)
        pump(0.6)
        record("bubble shows the left-half help after the pause", shows(.leftHalf),
               "\(controller.helpForTesting.map { "\($0.title) | \($0.detail) | \($0.hint)" } ?? "nothing")")

        // Placement: just below the button, left edges lined up (both in Accessibility coordinates).
        if let bubble = bubbleFrame(), let buttonFrame = panelFramesAbove(window).first {
            let gap = bubble.minY - buttonFrame.maxY
            record("bubble sits just below the button", gap >= 0 && gap <= 6, "gap \(gap) pt, bubble \(fmt(bubble)), button \(fmt(buttonFrame))")
            record("bubble is left-aligned with the button", abs(bubble.minX - buttonFrame.minX) <= 1)
        }

        hover(.mouseExited, left)
        pump(0.3)
        record("bubble goes when the pointer leaves", bubbleFrame() == nil)

        // Leaving before the pause is up cancels it.
        hover(.mouseEntered, left)
        pump(0.15)
        hover(.mouseExited, left)
        pump(0.8)
        record("leaving early cancels the bubble", bubbleFrame() == nil)

        // Pressing the button dismisses it.
        hover(.mouseEntered, left)
        pump(0.7)
        record("bubble is up again", shows(.leftHalf))
        if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 8, y: 8), modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: left.panel.windowNumber,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
           let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 200, y: 200), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: left.panel.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            left.button.mouseDown(with: down)
            pump(0.2)
            record("pressing the button hides the bubble", bubbleFrame() == nil)
            left.button.mouseUp(with: up)   // released outside the button: no click, just resets the look
        }
        hover(.mouseExited, left)

        // With Option held the left button is the left THIRD, and its help says how to go back.
        held = [.option]
        pump(0.4)
        hover(.mouseEntered, left)
        pump(0.7)
        record("Option held: bubble shows the left-third help", shows(.leftThird),
               "\(controller.helpForTesting.map { "\($0.detail) | \($0.hint)" } ?? "nothing")")

        // Releasing Option under the hovering pointer updates the bubble in place.
        held = []
        pump(0.5)
        record("releasing Option updates the bubble to the left-half help", shows(.leftHalf),
               "\(controller.helpForTesting.map { "\($0.detail) | \($0.hint)" } ?? "nothing")")
        hover(.mouseExited, left)
        pump(0.2)

        // A bubble for a button that disappears goes with it: hover the middle button, then drop it.
        held = [.option]
        pump(0.4)
        if let middle = button(1) {
            hover(.mouseEntered, middle)
            pump(0.7)
            record("middle button shows the center-third help", shows(.centerThird))
            held = []
            pump(0.5)
            record("bubble goes when its button is removed", bubbleFrame() == nil)
        } else {
            record("middle button exists while Option is held", false)
        }

        // Thirds as the default changes the hint wording.
        controller.thirdsByDefault = true
        pump(0.4)
        if let thirdsLeft = button(0) {
            hover(.mouseEntered, thirdsLeft)
            pump(0.7)
            record("thirds default: bubble says how to get halves", shows(.leftThird, thirdsByDefault: true),
                   "\(controller.helpForTesting?.hint ?? "nothing")")
            hover(.mouseExited, thirdsLeft)
        }
        controller.thirdsByDefault = false

        finish()
    }

    // MARK: Halves / thirds self-test

    /// Drives the real overlay controller with a throwaway window and a faked Option key.
    private static func selfTestModes(report file: URL) {
        var report = "AX trusted: \(AXIsProcessTrusted())\n"
        var failures = 0
        func record(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            report += "\(label): \(ok ? "OK" : "FAIL") \(detail)\n"
        }
        func finish(_ controller: OverlayController, _ window: NSWindow) {
            report += failures == 0 ? "ALL PASSED\n" : "\(failures) FAILED\n"
            controller.stop()
            window.close()
            try? report.write(to: file, atomically: true, encoding: .utf8)
        }

        var held: NSEvent.ModifierFlags = []
        let controller = OverlayController()
        controller.includesOwnWindows = true
        controller.modifierFlags = { held }
        controller.start()

        let window = makeTestWindow(title: "GreenTile modes test")
        pump(2.0)   // first scan + panel creation

        guard let ax = ownStandardWindow(), let initialLights = trafficLights(of: ax) else {
            record("find the test window and its traffic lights", false)
            finish(controller, window); return
        }
        report += "test window traffic lights: \(fmt(initialLights))\n"

        // Each button must be centred under its own light, at the size of a traffic light. The
        // lights are measured afresh each time: the clicks below move the window.
        func checkRow(_ label: String, columns: [Int]) {
            guard let lights = trafficLights(of: ax) else { record(label, false, "no traffic lights"); return }
            let actual = panelFramesAbove(window)
            let expected = columns.map { OverlayPlacement.frame(column: $0, trafficLights: lights) }
                .sorted { $0.minX < $1.minX }
            let ok = actual.count == expected.count
                && zip(actual, expected).allSatisfy { ScreenGeometry.framesMatch($0, $1, tolerance: 1) }
            record(label, ok, "expected \(expected.map(fmt)) got \(actual.map(fmt))")
        }

        checkRow("halves: buttons under red and green", columns: [0, 2])
        held = [.option]
        pump(0.4)
        checkRow("Option held: buttons under red, yellow and green", columns: [0, 1, 2])

        // Click each button through the real wiring, then read where the window actually went.
        let displays = Display.all()
        func click(_ label: String, column: Int, flags: NSEvent.ModifierFlags, expect: TileLayout) {
            guard let button = controller.panelForTesting(windowNumber: window.windowNumber, column: column)?.tileButton else {
                record(label, false, "no button in column \(column)"); return
            }
            button.onClick?(flags)
            pump(0.5)
            guard let frame = AX.frame(of: ax),
                  let index = ScreenGeometry.areaIndex(for: frame, in: displays.map(\.frame)) else {
                record(label, false, "no frame"); return
            }
            let expected = expect.frame(in: displays[index].usable)
            record(label, ScreenGeometry.framesMatch(expected, frame, tolerance: 1),
                   "expected \(fmt(expected)) got \(fmt(frame))")
        }
        click("left third button (Option held)", column: 0, flags: [.option], expect: .leftThird)
        click("center third button (Option held)", column: 1, flags: [.option], expect: .centerThird)
        click("right third button (Option held)", column: 2, flags: [.option], expect: .rightThird)

        held = []
        pump(0.4)
        checkRow("Option released: back to red and green", columns: [0, 2])
        record("the middle button is gone",
               controller.panelForTesting(windowNumber: window.windowNumber, column: 1) == nil)

        click("Option-click the left HALF button", column: 0, flags: [.option], expect: .leftThird)
        click("Option-click the right HALF button", column: 2, flags: [.option], expect: .rightThird)
        click("plain click left half", column: 0, flags: [], expect: .leftHalf)
        click("plain click right half", column: 2, flags: [], expect: .rightHalf)

        // --- Right-click toggles halves/thirds. Events are delivered straight to the button view, so
        //     the real mouse-handling code runs without injecting any system input. ---
        func event(_ type: NSEvent.EventType, on panel: OverlayPanel, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2),
                               modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)
        }
        func rightClick(_ label: String, expectingColumns columns: [Int]) {
            guard let panel = controller.panelForTesting(windowNumber: window.windowNumber, column: 0),
                  let up = event(.rightMouseUp, on: panel) else { record(label, false, "no button"); return }
            panel.tileButton.rightMouseUp(with: up)
            pump(0.4)
            checkRow(label, columns: columns)
        }
        rightClick("right-click switches to thirds", expectingColumns: [0, 1, 2])
        record("default mode is now thirds", controller.thirdsByDefault)
        rightClick("right-click again goes back to halves", expectingColumns: [0, 2])
        record("default mode is back to halves", !controller.thirdsByDefault)

        if let panel = controller.panelForTesting(windowNumber: window.windowNumber, column: 0),
           let up = event(.leftMouseUp, on: panel, flags: [.control]) {
            panel.tileButton.mouseUp(with: up)   // Control-click is a right-click on the Mac
            pump(0.4)
            checkRow("Control-click also switches to thirds", columns: [0, 1, 2])
            rightClick("right-click back to halves", expectingColumns: [0, 2])
        } else {
            record("Control-click", false, "no button")
        }

        // --- With thirds as the default, Option turns the row over to halves. ---
        rightClick("thirds as the default", expectingColumns: [0, 1, 2])
        held = [.option]
        pump(0.4)
        checkRow("Option held while thirds are the default: halves", columns: [0, 2])
        click("click left button with Option (thirds default) = left HALF", column: 0, flags: [.option], expect: .leftHalf)
        click("click right button with Option (thirds default) = right HALF", column: 2, flags: [.option], expect: .rightHalf)
        held = []
        pump(0.4)
        checkRow("Option released: thirds again", columns: [0, 1, 2])
        click("plain click left button (thirds default) = left third", column: 0, flags: [], expect: .leftThird)
        click("plain click middle button (thirds default) = center third", column: 1, flags: [], expect: .centerThird)
        rightClick("right-click restores halves", expectingColumns: [0, 2])

        // --- A real left-button mouse-up event with Option held, delivered to the left button. ---
        if let panel = controller.panelForTesting(windowNumber: window.windowNumber, column: 0),
           let up = event(.leftMouseUp, on: panel, flags: [.option]) {
            panel.tileButton.mouseUp(with: up)
            pump(0.5)
            if let frame = AX.frame(of: ax),
               let index = ScreenGeometry.areaIndex(for: frame, in: displays.map(\.frame)) {
                let expected = TileLayout.leftThird.frame(in: displays[index].usable)
                record("left-button mouse-up event with Option = left third",
                       ScreenGeometry.framesMatch(expected, frame, tolerance: 1),
                       "expected \(fmt(expected)) got \(fmt(frame))")
            }
        }

        finish(controller, window)
    }

    // MARK: Stacking self-test

    /// Are both halves buttons directly in front of `window` in the system's front-to-back list?
    private static func buttonsAreDirectlyAbove(_ window: NSWindow) -> Bool {
        let frames = panelFramesAbove(window)
        let side = OverlayPlacement.hitSize
        return frames.count == TileMode.halves.slots.count && frames.allSatisfy { $0.size == CGSize(width: side, height: side) }
    }

    /// Runs the real overlay controller against a throwaway window and re-fronts that window
    /// repeatedly, the way activation and clicks do, checking that the buttons come back in front
    /// of it every time. Foreground windows losing their buttons is what this guards against.
    private static func selfTestStacking(report file: URL) {
        var report = "AX trusted: \(AXIsProcessTrusted())\n"
        let controller = OverlayController()
        controller.includesOwnWindows = true
        controller.start()

        let window = makeTestWindow(title: "GreenTile stacking test")
        pump(2.0)

        var failures = 0
        func check(_ label: String, after delay: TimeInterval) {
            pump(delay)
            let actual = buttonsAreDirectlyAbove(window)
            if !actual { failures += 1 }
            report += "\(label): buttons above window = \(actual) \(actual ? "OK" : "FAIL")\n"
        }

        check("initial", after: 0)
        for round in 1...6 {
            // What activation / a click in the window does: bring it to the front of its level.
            window.orderFront(nil)
            pump(0.02)
            report += "round \(round) just after orderFront: buttons above = \(buttonsAreDirectlyAbove(window))\n"
            check("round \(round) +0.3 s", after: 0.3)
        }
        // A burst of re-fronting with no pause, then settle.
        for _ in 1...10 { window.orderFront(nil); pump(0.01) }
        check("after burst +0.3 s", after: 0.3)

        report += failures == 0 ? "ALL PASSED\n" : "\(failures) FAILED\n"
        controller.stop()
        window.close()
        try? report.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: Tiling self-test

    /// Creates a throwaway window of our own, tiles it to every layout on every display through the
    /// real `WindowActions` code path, and records whether the frame landed where it should.
    /// No other app's windows are touched.
    private static func selfTestTile(report file: URL) {
        var report = "AX trusted: \(AXIsProcessTrusted())\n"
        let displays = Display.all()
        let window = makeTestWindow(title: "GreenTile tile test")
        pump(0.6)

        guard let ax = ownStandardWindow() else {
            report += "FAIL: could not get the test window through Accessibility\n"
            try? report.write(to: file, atomically: true, encoding: .utf8)
            return
        }

        var failures = 0
        for (index, display) in displays.enumerated() {
            // Park the window mid-display first, so "which display is it on" is exercised too.
            let start = CGRect(x: display.usable.midX - 300, y: display.usable.midY - 200, width: 600, height: 400)
            AX.setFrame(ax, to: start)
            pump(0.3)
            for layout in TileLayout.allCases {
                WindowActions.tile(ax, layout)
                pump(0.4)
                let expected = layout.frame(in: display.usable)
                let actual = AX.frame(of: ax) ?? .zero
                let ok = ScreenGeometry.framesMatch(expected, actual, tolerance: 1)
                if !ok { failures += 1 }
                report += "display \(index) \(layout.title): expected \(fmt(expected)) got \(fmt(actual)) \(ok ? "OK" : "FAIL")\n"
            }
        }
        report += failures == 0 ? "ALL PASSED\n" : "\(failures) FAILED\n"
        window.close()
        try? report.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: Rendering

    /// Traffic lights as macOS draws them: three 16pt buttons 7pt apart.
    private static let mockLights = CGRect(x: 22, y: 16, width: 62, height: 16)

    private final class MockWindowCorner: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
            for (i, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: CGRect(x: DebugTools.mockLights.minX + CGFloat(i) * 23,
                                            y: DebugTools.mockLights.minY, width: 16, height: 16)).fill()
            }
        }
    }

    /// Renders `view` into a PNG at `scale` times its size.
    private static func writePNG(of view: NSView, scale: CGFloat, to url: URL) {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(view.bounds.width * scale),
                                         pixelsHigh: Int(view.bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    /// A close-up of the three button looks (normal, hover, pressed) for each half and third.
    private static func renderStates(into directory: URL) {
        let styles: [(name: String, appearance: NSAppearance.Name, background: NSColor)] = [
            ("light", .aqua, NSColor(white: 0.93, alpha: 1)),
            ("dark", .darkAqua, NSColor(white: 0.17, alpha: 1)),
        ]
        let side = OverlayPlacement.hitSize
        let layouts: [TileLayout] = [.leftHalf, .rightHalf, .leftThird, .centerThird]
        let states: [(hover: Bool, press: Bool)] = [(false, false), (true, false), (false, true)]
        for style in styles {
            let sheet = NSView(frame: CGRect(x: 0, y: 0, width: CGFloat(layouts.count) * (side + 6) + 6,
                                             height: CGFloat(states.count) * (side + 6) + 6))
            sheet.appearance = NSAppearance(named: style.appearance)
            sheet.wantsLayer = true
            sheet.layer?.backgroundColor = style.background.cgColor
            for (row, state) in states.enumerated() {
                for (column, layout) in layouts.enumerated() {
                    let button = TileButton(layout: layout)
                    button.setPreviewState(hovering: state.hover, pressed: state.press)
                    button.frame = CGRect(x: 6 + CGFloat(column) * (side + 6), y: 6 + CGFloat(row) * (side + 6),
                                          width: side, height: side)
                    sheet.addSubview(button)
                }
            }
            writePNG(of: sheet, scale: 16, to: directory.appendingPathComponent("overlay-states-\(style.name).png"))
        }
    }

    /// The help bubble as it looks for a half and for a third, on light and dark backgrounds.
    private static func renderHelp(into directory: URL) {
        let styles: [(name: String, appearance: NSAppearance.Name, background: NSColor)] = [
            ("light", .aqua, NSColor(white: 0.93, alpha: 1)),
            ("dark", .darkAqua, NSColor(white: 0.17, alpha: 1)),
        ]
        for style in styles {
            for (layout, thirdsByDefault) in [(TileLayout.leftHalf, false), (.centerThird, true)] {
                let bubble = HelpBubbleView(help: ButtonHelp(for: layout, thirdsByDefault: thirdsByDefault))
                let margin: CGFloat = 12
                let host = NSView(frame: CGRect(x: 0, y: 0, width: bubble.preferredSize.width + 2 * margin,
                                                height: bubble.preferredSize.height + 2 * margin))
                host.appearance = NSAppearance(named: style.appearance)
                host.wantsLayer = true
                host.layer?.backgroundColor = style.background.cgColor
                bubble.frame.origin = CGPoint(x: margin, y: margin)
                host.addSubview(bubble)
                writePNG(of: host, scale: 4, to: directory.appendingPathComponent("help-\(layout.rawValue)-\(style.name).png"))
            }
        }
    }

    private static func renderOverlay(into directory: URL) {
        renderHelp(into: directory)
        renderStates(into: directory)
        let styles: [(name: String, appearance: NSAppearance.Name, background: NSColor)] = [
            ("light", .aqua, NSColor(white: 0.93, alpha: 1)),
            ("dark", .darkAqua, NSColor(white: 0.17, alpha: 1)),
        ]
        for mode in TileMode.allCases {
            for style in styles {
                let corner = MockWindowCorner(frame: CGRect(x: 0, y: 0, width: 120, height: 70))
                corner.appearance = NSAppearance(named: style.appearance)
                corner.wantsLayer = true
                corner.layer?.backgroundColor = style.background.cgColor

                // Place each button exactly where the app would.
                for slot in mode.slots {
                    let button = TileButton(layout: slot.layout)
                    button.frame = OverlayPlacement.frame(column: slot.column, trafficLights: mockLights)
                    corner.addSubview(button)
                }

                let scale: CGFloat = 8   // the buttons are small; render large enough to inspect
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: Int(corner.bounds.width * scale),
                                                 pixelsHigh: Int(corner.bounds.height * scale),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                rep.size = corner.bounds.size
                corner.cacheDisplay(in: corner.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("overlay-\(mode)-\(style.name).png"))
                }
            }
        }
    }

    // MARK: Accessibility report

    private static func dumpWindows(to file: URL) {
        var report = "AX trusted: \(AXIsProcessTrusted())\n"
        let displayFrames = Display.all().map(\.frame)
        let candidates = WindowCatalog.onScreen().filter {
            $0.layer == 0 && !$0.isOwn
                && OverlayPlacement.isEligible(windowBounds: $0.bounds, displayFrames: displayFrames)
        }
        report += "eligible windows on screen: \(candidates.count)\n"
        let result = WindowScanner.scan(candidates)
        report += "windows that qualify for buttons: \(result.tracked.count)\n\n"
        for window in candidates {
            let app = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "pid \(window.pid)"
            var line = "#\(window.id) \(app) bounds=\(fmt(window.bounds))"
            if let info = result.tracked[window.id] {
                let lights = info.lightsRect.offsetBy(dx: window.bounds.minX, dy: window.bounds.minY)
                line += "\n    traffic lights: \(fmt(lights))"
                for column in 0...2 {
                    line += "\n      column \(column): button panel at \(fmt(OverlayPlacement.frame(column: column, trafficLights: lights)))"
                }
            } else {
                line += "\n    (no green button / not tileable)"
            }
            report += line + "\n"
        }
        try? report.write(to: file, atomically: true, encoding: .utf8)
    }
}
#endif
