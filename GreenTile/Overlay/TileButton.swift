import AppKit
import GreenTileKit

/// One tiling button, drawn like the green traffic light at three quarters of the size: a round,
/// softly shaded button with a darker rim, filled green for the part of the screen the window will
/// take and white for the rest. The view is the size of a traffic light, so the click target is
/// larger than the circle drawn in its middle.
final class TileButton: NSView {
    // Traffic-light greens: lit at the top, deeper at the bottom, with a darker rim.
    private static let greenTop = NSColor(srgbRed: 0.27, green: 0.83, blue: 0.35, alpha: 1)
    private static let greenBottom = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.25, alpha: 1)
    private static let rimTop = NSColor(srgbRed: 0.15, green: 0.69, blue: 0.22, alpha: 1)
    private static let rimBottom = NSColor(srgbRed: 0.09, green: 0.57, blue: 0.16, alpha: 1)
    // The white half is white at the top and a touch grey at the bottom, to match the same light.
    private static let whiteTop = NSColor.white
    private static let whiteBottom = NSColor(srgbRed: 0.88, green: 0.90, blue: 0.88, alpha: 1)

    /// What the button tiles to. It changes when Option swaps halves for thirds.
    var layout: TileLayout {
        didSet {
            guard layout != oldValue else { return }
            setAccessibilityLabel(layout.title)
            needsDisplay = true
        }
    }
    /// Called on a click, with the modifier keys held at that moment (Option flips halves/thirds).
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    /// Called on a right-click (or Control-click): switches between halves and thirds.
    var onSecondaryClick: (() -> Void)?

    /// Called with true when the pointer enters the button and false when it leaves. The help
    /// bubble follows this.
    var onHoverChange: ((Bool) -> Void)?
    /// Called when a mouse button goes down on the button (the help bubble gets out of the way).
    var onPress: (() -> Void)?

    private(set) var isHovering = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(layout: TileLayout) {
        self.layout = layout
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(layout.title)
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

    override func rightMouseDown(with event: NSEvent) {
        isPressed = true
        onPress?()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        guard contains(event) else { return }
        // Control-click is a right-click on the Mac.
        if event.modifierFlags.contains(.control) {
            onSecondaryClick?()
        } else {
            onClick?(event.modifierFlags)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        isPressed = false
        guard contains(event) else { return }
        onSecondaryClick?()
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    #if DEBUG
    /// Lets the preview render show the hover and pressed looks without a real pointer.
    func setPreviewState(hovering: Bool, pressed: Bool) {
        isHovering = hovering
        isPressed = pressed
    }
    #endif

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Hovering darkens the button a little and pressing a little more, as the system's do.
        let shade: CGFloat = isPressed ? 0.17 : (isHovering ? 0.07 : 0)
        func tone(_ color: NSColor) -> NSColor { color.blended(withFraction: shade, of: .black) ?? color }

        // The circle sits in the middle of the (larger) click area, nudged a little (this view is
        // flipped, so a negative offset is up on screen).
        let disc = bounds.insetBy(dx: OverlayPlacement.hitSlop, dy: OverlayPlacement.hitSlop)
            .offsetBy(dx: 0, dy: OverlayPlacement.circleNudgeY)
        let rimWidth: CGFloat = 0.8
        let inner = disc.insetBy(dx: rimWidth, dy: rimWidth)
        let outerPath = NSBezierPath(ovalIn: disc)
        let innerPath = NSBezierPath(ovalIn: inner)

        // 1. Rim, with a soft shadow underneath that lifts the button off the title bar. (View
        //    NSShadow offsets ignore the view's flip, so a negative height moves it down.)
        NSGraphicsContext.saveGraphicsState()
        if !isPressed {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 1.2
            shadow.shadowOffset = NSSize(width: 0, height: -0.6)
            shadow.set()
        }
        tone(Self.rimBottom).setFill()
        outerPath.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: tone(Self.rimTop), ending: tone(Self.rimBottom))?.draw(in: outerPath, angle: 90)

        // 2. Body: the white and green parts, each shaded from light (top) to deeper (bottom).
        NSGraphicsContext.saveGraphicsState()
        innerPath.addClip()
        NSGradient(starting: tone(Self.whiteTop), ending: tone(Self.whiteBottom))?.draw(in: inner, angle: 90)

        let slot = layout.slot
        let green = CGRect(x: inner.minX + slot.minX * inner.width, y: inner.minY,
                           width: slot.width * inner.width, height: inner.height)
        NSGradient(starting: tone(Self.greenTop), ending: tone(Self.greenBottom))?.draw(in: green, angle: 90)

        // 3. Gloss: a faint light fading out over the top half, like the system buttons. It is
        //    left off while pressed, when the button looks pushed in.
        if !isPressed {
            let gloss = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * 0.45)
            NSGradient(starting: NSColor.white.withAlphaComponent(0.30),
                       ending: NSColor.white.withAlphaComponent(0))?.draw(in: gloss, angle: 90)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
