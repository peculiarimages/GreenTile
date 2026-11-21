import AppKit
import GreenTileKit

/// A connected display in Accessibility coordinates.
struct Display {
    /// The display's name, e.g. "Thunderbolt Display".
    let name: String
    /// Full frame of the display.
    let frame: CGRect
    /// Area not covered by the menu bar or the Dock.
    let usable: CGRect

    /// AppKit measures y from the bottom of the primary display; Accessibility from its top.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func all() -> [Display] {
        let height = primaryHeight
        return NSScreen.screens.map {
            Display(name: $0.localizedName,
                    frame: ScreenGeometry.flip($0.frame, primaryHeight: height),
                    usable: ScreenGeometry.flip($0.visibleFrame, primaryHeight: height))
        }
    }
}
