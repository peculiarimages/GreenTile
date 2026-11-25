import ApplicationServices
import GreenTileKit

enum WindowActions {
    /// Space between the tile and the screen edge, in points.
    static let tileGap: CGFloat = 0

    /// Windows whose frame is a tile that `TileLayout.matching` cannot see: ones that would not
    /// shrink to their tile and were pinned to its outer edge, and ones resized together with a
    /// neighbour into a custom split. Each has the tile and the frame it ended up with, so Stage
    /// Manager snap-back still knows it is tiled.
    private(set) static var placed: [CGWindowID: (tile: Tile, frame: CGRect)] = [:]

    /// Records that window `id` now sits at `frame` as `tile`.
    static func remember(_ id: CGWindowID, as tile: Tile, at frame: CGRect) {
        placed[id] = (tile, frame)
    }

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
        tile(window, .layout(layout))
    }

    /// Puts `window` on `tile` on the display it is on.
    /// - Returns: the frame the window ended up with.
    @discardableResult
    static func tile(_ window: AXUIElement, _ tile: Tile) -> CGRect? {
        let displays = Display.all()
        guard let current = AX.frame(of: window),
              let index = ScreenGeometry.areaIndex(for: current, in: displays.map(\.frame)) else { return nil }
        let area = displays[index].usable
        let target = tile.frame(in: area, gap: tileGap)
        let result = place(window, at: target, in: area)
        if let id = AX.windowID(of: window) {
            var isCustom = false
            if case .custom = tile { isCustom = true }
            if let result, isCustom || ScreenGeometry.isOversized(result.size, for: target) {
                placed[id] = (tile, result)
            } else {
                placed[id] = nil
            }
        }
        AX.raise(window)
        return result
    }

    /// The tile a window was pinned or resized to, if it is still where it was put, or (for a
    /// custom split) on that same share of the display it is on now.
    static func placedTile(of id: CGWindowID, at frame: CGRect, in area: CGRect) -> Tile? {
        guard let entry = placed[id] else { return nil }
        if ScreenGeometry.framesMatch(entry.frame, frame, tolerance: 2) { return entry.tile }
        if case .custom = entry.tile,
           ScreenGeometry.framesMatch(entry.tile.frame(in: area, gap: tileGap), frame, tolerance: 2) { return entry.tile }
        return nil
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
