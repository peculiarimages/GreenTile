import AppKit
import ApplicationServices
import GreenTileKit

/// What the overlay needs to know about a window that is a candidate for the buttons.
struct TrackedWindow {
    let element: AXUIElement
    /// The rectangle spanning the close to zoom buttons, relative to the window's top-left corner
    /// (Accessibility orientation, y down). It does not change while the window moves.
    let lightsRect: CGRect
    /// How many consecutive scans failed to confirm this window. One miss is tolerated (an app
    /// that answers Accessibility slowly would otherwise make its buttons blink off).
    var staleScans = 0
}

/// Window discovery through the Quartz window list, which needs no Screen Recording permission
/// for ids, owners, layers and bounds.
enum WindowCatalog {
    struct Info {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        /// In Accessibility coordinates (origin top-left of the primary display).
        let bounds: CGRect
        /// One of this app's own windows (the button panels, mostly).
        var isOwn: Bool { pid == getpid() }
    }

    /// Every on-screen window of every level, front to back. This app's own windows are included
    /// (marked by `isOwn`): the stacking check has to see where the button panels are.
    static func onScreen() -> [Info] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return Info(id: number, pid: pid, layer: layer, bounds: bounds)
        }
    }
}

/// Resolves candidate windows to Accessibility elements and finds each one's green button.
/// Accessibility calls can block on a busy app, so this runs off the main thread.
enum WindowScanner {
    struct Result {
        /// Windows that should carry the buttons.
        var tracked: [CGWindowID: TrackedWindow] = [:]
        /// Every window that was looked at, whether or not it qualified. Windows missing from this
        /// set are new and trigger another scan.
        var examined: Set<CGWindowID> = []
    }

    /// `previous` is the last scan's outcome, used to ride out a single failed query.
    static func scan(_ candidates: [WindowCatalog.Info], previous: [CGWindowID: TrackedWindow] = [:]) -> Result {
        let wanted = Set(candidates.map(\.id))
        let pids = Array(Set(candidates.map(\.pid)))

        // Apps are queried in parallel so one slow or hung app does not delay the others.
        let lock = NSLock()
        var found: [CGWindowID: TrackedWindow] = [:]
        DispatchQueue.concurrentPerform(iterations: pids.count) { index in
            let app = AXUIElementCreateApplication(pids[index])
            AXUIElementSetMessagingTimeout(app, 0.6)
            // The first query to a process can time out cold; ask twice before giving up.
            guard let windows = AX.elementsIfAvailable(app, kAXWindowsAttribute)
                    ?? AX.elementsIfAvailable(app, kAXWindowsAttribute) else { return }
            for window in windows {
                guard let id = AX.windowID(of: window), wanted.contains(id), let tracked = track(window) else { continue }
                lock.lock(); found[id] = tracked; lock.unlock()
            }
        }

        var result = Result()
        result.examined = wanted
        result.tracked = found
        for id in wanted where found[id] == nil {
            if var old = previous[id], old.staleScans < 1 {
                old.staleScans += 1
                result.tracked[id] = old
            }
        }
        return result
    }

    /// A window qualifies when it is an ordinary, resizable window with a visible green button.
    private static func track(_ window: AXUIElement) -> TrackedWindow? {
        guard AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              !AX.isFullScreen(window),
              AX.isSettable(window, kAXPositionAttribute),
              AX.isSettable(window, kAXSizeAttribute),
              let zoom = AX.zoomButton(of: window),
              let windowFrame = AX.frame(of: window),
              let zoomFrame = AX.frame(of: zoom),
              windowFrame.insetBy(dx: -1, dy: -1).contains(zoomFrame)
        else { return nil }
        // The cluster runs from the close button to the zoom button; without a close button the
        // zoom button alone stands in for it.
        let closeFrame = AX.element(window, kAXCloseButtonAttribute).flatMap { AX.frame(of: $0) }
        let lights = closeFrame.map { $0.union(zoomFrame) } ?? zoomFrame
        guard windowFrame.insetBy(dx: -1, dy: -1).contains(lights) else { return nil }
        let relative = lights.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
        return TrackedWindow(element: window, lightsRect: relative)
    }
}
