import ApplicationServices
import GreenTileKit

enum WindowActions {
    /// Space between the tile and the screen edge, in points.
    static let tileGap: CGFloat = 0

    /// Windows that would not shrink to their tile and were pinned to its outer edge instead: the
    /// layout they were tiled to and the frame they ended up with. A pinned window does not match
    /// its tile exactly, so this is how Stage Manager snap-back still knows it is tiled.
    private(set) static var pinned: [CGWindowID: (layout: TileLayout, frame: CGRect)] = [:]

    /// Sends `window` to the display on `side` of the one it is on. It keeps the same share of the
    /// new display's usable area, so a window tiled to a left half stays a left half there. Does
    /// nothing when there is no display on that side.
    static func move(_ window: AXUIElement, toward side: DisplaySide) {
        let displays = Display.all()
        let frames = displays.map(\.frame)
        guard let current = AX.frame(of: window),
              let index = ScreenGeometry.areaIndex(for: current, in: frames),
              let target = ScreenGeometry.neighbourIndex(of: index, on: side, in: frames, preferring: current)
        else { return }
        let area = displays[target].usable
        place(window, at: ScreenGeometry.mapProportionally(current, from: displays[index].usable, to: area), in: area)
        AX.raise(window)
    }

    /// Snaps `window` to the left or right half of the usable area of the display it is on.
    /// - Returns: the frame the window ended up with.
    @discardableResult
    static func tile(_ window: AXUIElement, _ layout: TileLayout) -> CGRect? {
        let displays = Display.all()
        guard let current = AX.frame(of: window),
              let index = ScreenGeometry.areaIndex(for: current, in: displays.map(\.frame)) else { return nil }
        let area = displays[index].usable
        let target = layout.frame(in: area, gap: tileGap)
        let result = place(window, at: target, in: area)
        if let id = AX.windowID(of: window) {
            if let result, ScreenGeometry.isOversized(result.size, for: target) {
                pinned[id] = (layout, result)
            } else {
                pinned[id] = nil
            }
        }
        AX.raise(window)
        return result
    }

    /// The tile a window was pinned to, if it is still exactly where it was pinned.
    static func pinnedLayout(of id: CGWindowID, at frame: CGRect) -> TileLayout? {
        guard let entry = pinned[id], ScreenGeometry.framesMatch(entry.frame, frame, tolerance: 2) else { return nil }
        return entry.layout
    }

    /// Sets `window` to `target`, then reads back what the app actually allowed. A window that
    /// stayed bigger than asked (a minimum size) is moved so that it sits against the same edge of
    /// `area` as `target`, instead of hanging off the display.
    @discardableResult
    private static func place(_ window: AXUIElement, at target: CGRect, in area: CGRect) -> CGRect? {
        AX.setFrame(window, to: target)
        guard let actual = AX.frame(of: window) else { return nil }
        guard ScreenGeometry.isOversized(actual.size, for: target) else { return actual }
        let anchored = ScreenGeometry.anchor(actual.size, to: target, in: area)
        AX.setPosition(window, anchored.origin)
        return AX.frame(of: window) ?? anchored
    }
}
