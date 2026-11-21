import ApplicationServices
import GreenTileKit

enum WindowActions {
    /// Space between the tile and the screen edge, in points.
    static let tileGap: CGFloat = 0

    /// Snaps `window` to the left or right half of the usable area of the display it is on.
    static func tile(_ window: AXUIElement, _ layout: TileLayout) {
        let displays = Display.all()
        guard let current = AX.frame(of: window),
              let index = ScreenGeometry.areaIndex(for: current, in: displays.map(\.frame)) else { return }
        AX.setFrame(window, to: layout.frame(in: displays[index].usable, gap: tileGap))
        AX.raise(window)
    }
}
