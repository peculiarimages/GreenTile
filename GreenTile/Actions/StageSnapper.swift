import AppKit
import ApplicationServices
import GreenTileKit

/// Puts a window back on its tile when Stage Manager brings it into the stage in front.
///
/// Stage Manager drops a window dragged in from the strip wherever the pointer lets go of it. When
/// that window was tiled (a left half, say) the last time it was on screen, this tiles it the same
/// way again once it has landed.
///
/// How it works, driven by the overlay's window poll:
/// * Every window on screen that has sat still for a moment, with no mouse button held, is checked
///   against the tiles of its display. A match is remembered; a window that is somewhere else
///   forgets its tile (the user moved it on purpose).
/// * A window that was not on screen in the previous poll has just arrived: from the strip, from
///   another Space, unhidden. If it has a remembered tile, it gets a few seconds to land, and is
///   then tiled again if it is not already there. A window that comes back where it was (switching
///   to its whole stage, for example) already matches and is left alone.
/// * A tiled window dragged onto another display lands wherever it is let go; once it has settled
///   there, it takes the same tile on that display (a left half becomes the left half there).
///   Dragged off its tile on the same display, it forgets the tile instead.
final class StageSnapper {
    /// Off means Stage Manager arrivals are only remembered, never moved.
    var isEnabled = true
    /// Off means a tiled window dragged to another display stays where it is dropped.
    var keepsTilesAcrossDisplays = true
    /// Called with the tile's frame (top-left screen coordinates) when a window is put back on it.
    var onSnap: ((CGRect) -> Void)?

    /// How long a window must keep the same frame before it counts as having landed.
    static let settleTime: CFTimeInterval = 0.3
    /// How long after arriving a window may still be put back on its tile.
    static let patience: CFTimeInterval = 4
    /// How many times to tile it before giving up (some apps resist, or Stage Manager moves the
    /// window again at the end of its animation).
    static let maxAttempts = 2

    private struct Seen {
        var bounds: CGRect
        var stableSince: CFTimeInterval
    }

    private struct Pending {
        var layout: TileLayout
        let deadline: CFTimeInterval
        var attempts = 0
        /// When it arrived from Stage Manager's strip, if it did (not for a move between displays).
        var arrivedAt: CFTimeInterval?
    }

    /// A press-and-drag of the mouse, in top-left screen coordinates.
    private struct Drag {
        var start: CGPoint
        var end: CGPoint
        var releasedAt: CFTimeInterval?
    }

    /// The drag in progress, or the last one let go.
    private var drag: Drag?
    /// How far the pointer must travel for a press to count as a drag rather than a click.
    static let dragDistance: CGFloat = 40

    private var seen: [CGWindowID: Seen] = [:]
    /// A window's tile and the display (index into `Display.all()`) it was on.
    private struct Remembered {
        let layout: TileLayout
        let display: Int
    }

    private var remembered: [CGWindowID: Remembered] = [:]
    private var pending: [CGWindowID: Pending] = [:]

    private var stageManagerCheckedAt: CFTimeInterval = -.infinity
    private var stageManagerCached = false

    /// Forgets which windows were on screen, so that nothing counts as arriving when the poll
    /// resumes after a pause (buttons hidden, permission lost). Remembered tiles are kept.
    func pause() {
        seen.removeAll()
        pending.removeAll()
    }

    /// Call on every poll with the ordinary windows on screen, front to back.
    /// - Returns: whether a window was moved.
    @discardableResult
    func update(windows: [WindowCatalog.Info], element: (CGWindowID) -> AXUIElement?,
                displays: [Display]) -> Bool {
        let now = CACurrentMediaTime()
        let frames = displays.map(\.frame)
        let mouseUp = NSEvent.pressedMouseButtons == 0
        trackDrag(mouseUp: mouseUp, now: now)
        var next: [CGWindowID: Seen] = [:]
        var moved = false

        for window in windows {
            let arrived = !seen.isEmpty && seen[window.id] == nil
            var state = seen[window.id] ?? Seen(bounds: window.bounds, stableSince: now)
            if state.bounds != window.bounds { state = Seen(bounds: window.bounds, stableSince: now) }
            defer { next[window.id] = state }

            if arrived, isEnabled, let tile = remembered[window.id], isStageManagerOn(now: now) {
                pending[window.id] = Pending(layout: tile.layout, deadline: now + Self.patience, arrivedAt: now)
            }

            guard mouseUp, now - state.stableSince >= Self.settleTime,
                  let index = ScreenGeometry.areaIndex(for: window.bounds, in: frames) else { continue }
            // A window pinned to its tile's edge (it would not shrink to fit) counts as tiled too.
            let current = TileLayout.matching(window.bounds, in: displays[index].usable, gap: WindowActions.tileGap)
                ?? WindowActions.pinnedLayout(of: window.id, at: window.bounds)
            let found = current.map { Remembered(layout: $0, display: index) }

            // Dragged onto another display and let go off any tile: take the old tile there.
            if pending[window.id] == nil, current == nil, keepsTilesAcrossDisplays,
               let tile = remembered[window.id], tile.display != index {
                pending[window.id] = Pending(layout: tile.layout, deadline: now + Self.patience)
            }

            if var wanted = pending[window.id] {
                // Dragged in from the strip: the side it was dropped on wins over the saved tile.
                if wanted.attempts == 0, let arrivedAt = wanted.arrivedAt,
                   let dropX = dropPoint(since: arrivedAt)?.x {
                    wanted.layout = wanted.layout.dropped(atX: dropX, in: displays[index].usable)
                }
                if current == wanted.layout || now > wanted.deadline || wanted.attempts >= Self.maxAttempts {
                    pending[window.id] = nil
                    remembered[window.id] = found
                    continue
                }
                guard let element = element(window.id) else { continue }
                let landed = WindowActions.tile(element, wanted.layout)
                if wanted.attempts == 0 {
                    // Where the window ended up: its tile, or pinned to the tile's edge if it is wider.
                    onSnap?(landed ?? wanted.layout.frame(in: displays[index].usable, gap: WindowActions.tileGap))
                }
                wanted.attempts += 1
                pending[window.id] = wanted
                // Judge the result only once it has settled in turn.
                state.stableSince = now
                moved = true
            } else {
                remembered[window.id] = found
            }
        }

        // Windows that left the screen keep their remembered tile: they may be in the strip.
        seen = next
        pending = pending.filter { next[$0.key] != nil || $0.value.deadline > now }
        // An empty first poll would make every later window look new; record it as "seen nothing".
        if seen.isEmpty { seen[kCGNullWindowID] = Seen(bounds: .zero, stableSince: now) }
        return moved
    }

    /// Follows the mouse button from poll to poll, keeping where a drag started and where it was
    /// let go.
    private func trackDrag(mouseUp: Bool, now: CFTimeInterval) {
        let location = ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: Display.primaryHeight)
        if !mouseUp {
            if drag == nil || drag?.releasedAt != nil {
                drag = Drag(start: location, end: location)
            } else {
                drag?.end = location
            }
        } else if drag != nil, drag?.releasedAt == nil {
            drag?.end = location
            drag?.releasedAt = now
        }
    }

    /// Where the pointer let go of a drag that ended around or after `arrival` (Stage Manager can
    /// bring the window on screen just before or just after the drop). A click on the strip, or a
    /// press that hardly moved, is not a drag.
    private func dropPoint(since arrival: CFTimeInterval) -> CGPoint? {
        guard let drag, let released = drag.releasedAt, released >= arrival - 1 else { return nil }
        let dx = drag.end.x - drag.start.x, dy = drag.end.y - drag.start.y
        guard (dx * dx + dy * dy).squareRoot() >= Self.dragDistance else { return nil }
        return drag.end
    }

    /// Whether Stage Manager is switched on. Read from its preferences at most every 2 s, and only
    /// when a remembered window arrives.
    private func isStageManagerOn(now: CFTimeInterval) -> Bool {
        if now - stageManagerCheckedAt > 2 {
            stageManagerCheckedAt = now
            stageManagerCached = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        }
        return stageManagerCached
    }
}

/// GreenTile's icon, shown for a moment in the middle of a window that GreenTile has just put back
/// on its tile, so it is clear the move was GreenTile's doing and not the app's or macOS's.
final class SnapBadge {
    static let size: CGFloat = 192

    private let panel: NSPanel
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        // The artwork at the full size it was made at, so it stays sharp at this size on a Retina
        // screen. It is the icon's rounded square without the icon's transparent margin, so it is
        // drawn inset by that margin (100 of 1024) to look the same size as the app icon would.
        let inset = Self.size * 100 / 1024
        let image = NSImageView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size).insetBy(dx: inset, dy: inset))
        image.image = NSImage(named: "SnapBadge") ?? NSApp.applicationIconImage
        image.imageScaling = .scaleProportionallyUpOrDown
        image.wantsLayer = true
        image.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            return shadow
        }()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        content.addSubview(image)
        panel.contentView = content
    }

    /// Fades the icon in at the centre of `frame` (AppKit screen coordinates), holds it, fades it out.
    func show(centeredIn frame: CGRect) {
        generation += 1
        let mine = generation
        let side = Self.size
        panel.setFrame(NSRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side),
                       display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.generation == mine else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == mine else { return }
                self.panel.orderOut(nil)
            })
        }
    }
}
