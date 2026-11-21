import AppKit
import GreenTileKit

/// A borderless panel that never takes focus, so clicking a button leaves the active app alone.
/// It lives at the normal window level and is ordered directly above its own window, which means
/// other windows that cover that window also cover the button. One panel per button (rather than
/// one wide panel per window) keeps the empty space between buttons genuinely empty: clicks there
/// reach the window beneath.
class ButtonPanel: NSPanel {
    /// The window this button belongs to.
    var targetWindow: AXUIElement?

    init(content: NSView) {
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
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A panel holding one round tiling button.
final class OverlayPanel: ButtonPanel {
    let tileButton: TileButton

    var layout: TileLayout { tileButton.layout }

    init(layout: TileLayout) {
        tileButton = TileButton(layout: layout)
        super.init(content: tileButton)
    }
}

/// A panel holding a chevron that sends the window to the neighbouring display.
final class ChevronPanel: ButtonPanel {
    let chevronButton: ChevronButton
    /// The neighbouring display's name, for the help bubble.
    var neighbourName = ""

    var side: DisplaySide { chevronButton.side }

    init(side: DisplaySide) {
        chevronButton = ChevronButton(side: side)
        super.init(content: chevronButton)
    }
}
