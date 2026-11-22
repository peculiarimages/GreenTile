import AppKit
import GreenTileKit

/// One tiling button, drawn like the green traffic light at three quarters of the size: a round,
/// softly shaded button with a darker rim, filled green for the part of the screen the window will
/// take and white for the rest. The view is the size of a traffic light, so the click target is
/// larger than the circle drawn in its middle.
final class TileButton: NSView {
    // Colours come from `ButtonPalette` (the green fill and its 33%-black outline are defined once,
    // in `ButtonColors`, and shared with the chevrons).

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

    /// True while the window this belongs to is not the active one: the colours lose a third of
    /// their colour so the active window's buttons stand out.
    var isMuted = false { didSet { if isMuted != oldValue { needsDisplay = true } } }

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
        func tone(_ color: NSColor) -> NSColor {
            let base = isMuted ? color.mutedForBackground() : color
            return base.blended(withFraction: shade, of: .black) ?? base
        }

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
        tone(ButtonPalette.outline).setFill()
        outerPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 2. Body: the white and green parts, each shaded from light (top) to deeper (bottom).
        NSGraphicsContext.saveGraphicsState()
        innerPath.addClip()
        NSGradient(starting: tone(ButtonPalette.whiteTop), ending: tone(ButtonPalette.whiteBottom))?.draw(in: inner, angle: 90)

        let slot = layout.slot
        let green = CGRect(x: inner.minX + slot.minX * inner.width, y: inner.minY,
                           width: slot.width * inner.width, height: inner.height)
        NSGradient(starting: tone(ButtonPalette.fillTop), ending: tone(ButtonPalette.fillBottom))?.draw(in: green, angle: 90)

        // 3. Gloss: a faint light fading out over the top half, like the system buttons. It is
        //    left off while pressed, when the button looks pushed in.
        if !isPressed {
            let gloss = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * 0.45)
            NSGradient(starting: NSColor.white.withAlphaComponent(ButtonPalette.glossAlpha),
                       ending: NSColor.white.withAlphaComponent(0))?.draw(in: gloss, angle: 90)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
