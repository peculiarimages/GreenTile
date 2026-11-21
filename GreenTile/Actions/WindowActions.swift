import ApplicationServices
import GreenTileKit

enum WindowActions {
    /// Space between the tile and the screen edge, in points.
    static let tileGap: CGFloat = 0

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
        AX.setFrame(window, to: ScreenGeometry.mapProportionally(current, from: displays[index].usable,
                                                                 to: displays[target].usable))
        AX.raise(window)
    }

    /// Snaps `window` to the left or right half of the usable area of the display it is on.
    static func tile(_ window: AXUIElement, _ layout: TileLayout) {
        let displays = Display.all()
        guard let current = AX.frame(of: window),
              let index = ScreenGeometry.areaIndex(for: current, in: displays.map(\.frame)) else { return }
        AX.setFrame(window, to: layout.frame(in: displays[index].usable, gap: tileGap))
        AX.raise(window)
    }
}
