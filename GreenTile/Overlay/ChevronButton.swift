import AppKit
import GreenTileKit

/// A small chevron (`‹` or `›`) that sends the window to the display on that side. It matches the
/// round tiling buttons: the same green with a darker rim, a soft shadow, darker while hovered and
/// pressed, and the same click-area height.
final class ChevronButton: NSView {
    let side: DisplaySide
    /// Called on a click.
    var onClick: (() -> Void)?
    /// Called with true when the pointer enters the button and false when it leaves.
    var onHoverChange: ((Bool) -> Void)?
    /// Called when a mouse button goes down on the button (the help bubble gets out of the way).
    var onPress: (() -> Void)?

    private(set) var isHovering = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(side: DisplaySide) {
        self.side = side
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(side == .left ? "Move to Left Display" : "Move to Right Display")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        onPress?()
    }

    override func rightMouseDown(with event: NSEvent) { onPress?() }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let shade: CGFloat = isPressed ? 0.17 : (isHovering ? 0.07 : 0)
        func tone(_ color: NSColor) -> NSColor { color.blended(withFraction: shade, of: .black) ?? color }

        // Centred in the click area and, vertically, level with the tiling buttons' circles.
        let centre = CGPoint(x: bounds.midX, y: bounds.midY + OverlayPlacement.circleNudgeY)
        let reach: CGFloat = 2.6      // how far the tip sticks out horizontally
        let halfHeight: CGFloat = 4.4
        let tipX = centre.x + (side == .left ? -reach : reach)
        let tailX = centre.x + (side == .left ? reach : -reach)

        let path = NSBezierPath()
        path.move(to: CGPoint(x: tailX, y: centre.y - halfHeight))
        path.line(to: CGPoint(x: tipX, y: centre.y))
        path.line(to: CGPoint(x: tailX, y: centre.y + halfHeight))
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // A darker, wider stroke underneath forms the rim and casts the soft shadow (NSShadow
        // offsets ignore the view's flip, so a negative height moves it down).
        NSGraphicsContext.saveGraphicsState()
        if !isPressed {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 1.2
            shadow.shadowOffset = NSSize(width: 0, height: -0.6)
            shadow.set()
        }
        tone(ButtonPalette.outline).setStroke()
        path.lineWidth = 3.6
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        tone(ButtonPalette.fill).setStroke()
        path.lineWidth = 2.1
        path.stroke()
    }
}
