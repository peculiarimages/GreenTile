import AppKit
import GreenTileKit

/// A borderless panel holding a single round button, the size of a traffic light.
///
/// It never takes focus, so clicking leaves the active app alone. It lives at the normal window
/// level and is ordered directly above its own window, which means other windows that cover that
/// window also cover the button. One panel per button (rather than one wide panel per window)
/// keeps the empty space between buttons genuinely empty: clicks there reach the window beneath.
final class OverlayPanel: NSPanel {
    /// The window this button belongs to.
    var targetWindow: AXUIElement?
    let tileButton: TileButton

    var layout: TileLayout { tileButton.layout }

    init(layout: TileLayout) {
        tileButton = TileButton(layout: layout)
        let side = OverlayPlacement.hitSize
        super.init(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // the system's traffic lights cast none either
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        contentView = tileButton
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
