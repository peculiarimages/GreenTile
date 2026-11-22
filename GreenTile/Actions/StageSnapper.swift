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
final class StageSnapper {
    /// Off means windows are only remembered, never moved.
    var isEnabled = true

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
        let layout: TileLayout
        let deadline: CFTimeInterval
        var attempts = 0
    }

    private var seen: [CGWindowID: Seen] = [:]
    private var remembered: [CGWindowID: TileLayout] = [:]
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
        var next: [CGWindowID: Seen] = [:]
        var moved = false

        for window in windows {
            let arrived = !seen.isEmpty && seen[window.id] == nil
            var state = seen[window.id] ?? Seen(bounds: window.bounds, stableSince: now)
            if state.bounds != window.bounds { state = Seen(bounds: window.bounds, stableSince: now) }
            defer { next[window.id] = state }

            if arrived, isEnabled, let layout = remembered[window.id], isStageManagerOn(now: now) {
                pending[window.id] = Pending(layout: layout, deadline: now + Self.patience)
            }

            guard mouseUp, now - state.stableSince >= Self.settleTime,
                  let index = ScreenGeometry.areaIndex(for: window.bounds, in: frames) else { continue }
            let current = TileLayout.matching(window.bounds, in: displays[index].usable, gap: WindowActions.tileGap)

            if var wanted = pending[window.id] {
                if current == wanted.layout || now > wanted.deadline || wanted.attempts >= Self.maxAttempts {
                    pending[window.id] = nil
                    remembered[window.id] = current
                    continue
                }
                guard let element = element(window.id) else { continue }
                WindowActions.tile(element, wanted.layout)
                wanted.attempts += 1
                pending[window.id] = wanted
                // Judge the result only once it has settled in turn.
                state.stableSince = now
                moved = true
            } else {
                remembered[window.id] = current
            }
        }

        // Windows that left the screen keep their remembered tile: they may be in the strip.
        seen = next
        pending = pending.filter { next[$0.key] != nil || $0.value.deadline > now }
        // An empty first poll would make every later window look new; record it as "seen nothing".
        if seen.isEmpty { seen[kCGNullWindowID] = Seen(bounds: .zero, stableSince: now) }
        return moved
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
