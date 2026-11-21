import AppKit
import GreenTileKit

/// The contents of the help bubble: a bold name, what a click does, and a quieter hint line.
final class HelpBubbleView: NSVisualEffectView {
    private(set) var preferredSize: CGSize = .zero

    init(help: ButtonHelp) {
        super.init(frame: .zero)
        material = .toolTip
        blendingMode = .behindWindow
        state = .active
        maskImage = Self.roundedMask(radius: 6)

        let labels = [
            Self.label(help.title, font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor),
            Self.label(help.detail, font: .systemFont(ofSize: 11), color: .labelColor),
            Self.label(help.hint, font: .systemFont(ofSize: 11), color: .secondaryLabelColor),
        ]
        let padX: CGFloat = 10, padY: CGFloat = 7, spacing: CGFloat = 2
        let textWidth = labels.map { $0.intrinsicContentSize.width }.max() ?? 0
        let textHeight = labels.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.height } + spacing * CGFloat(labels.count - 1)
        // A few points of slack: a text field clips its last glyph if its frame is exactly as wide as
        // the measured text.
        let size = CGSize(width: ceil(textWidth) + 2 * padX + 6, height: ceil(textHeight) + 2 * padY)
        setFrameSize(size)
        preferredSize = size

        // This view is not flipped, so lay the labels out from the top down.
        var y = size.height - padY
        for label in labels {
            let height = label.intrinsicContentSize.height
            y -= height
            label.frame = CGRect(x: padX, y: y, width: size.width - 2 * padX, height: height)
            addSubview(label)
            y -= spacing
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        return field
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Shows the help bubble just below a button once the pointer has rested on it for a moment, and
/// takes it away again. (The standard tooltip machinery is unreliable for a background app's
/// non-activating panels, so this draws its own.)
///
/// Once it is up it stays while the pointer is on the bubble or on its button, and goes when the
/// pointer has been away from both for `awayDelay`. The bubble itself ignores mouse events so it
/// never blocks a click on the window beneath, which means "the pointer is on it" is worked out by
/// watching where the pointer is rather than from mouse events.
final class HelpBubble {
    /// Pause before the bubble first appears: the same as a standard tooltip.
    static let delay: TimeInterval = 0.45
    /// Pause when moving from one button to the next while a bubble is already up.
    static let switchDelay: TimeInterval = 0.12
    /// How long the pointer may stay away from both the bubble and its button before it hides.
    static let awayDelay: TimeInterval = 2

    private let window: NSPanel
    private var pending: DispatchWorkItem?
    private var watcher: Timer?
    private var awaySince: CFTimeInterval?
    /// The button panel the bubble is for, from when it is scheduled until it is hidden.
    private weak var owner: OverlayPanel?
    /// The text on show, for the self-test.
    private(set) var current: ButtonHelp?

    /// Where the pointer is, in screen coordinates. Replaced only by the self-test.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.ignoresMouseEvents = true      // never in the way of a click
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    // MARK: Pointer events from the button

    /// The pointer arrived on `owner`'s button.
    func hoverBegan(for owner: OverlayPanel, help: ButtonHelp) {
        // Already up for this very button (the pointer left and came straight back): keep it as
        // it is rather than hiding and re-showing it.
        if self.owner === owner, window.isVisible {
            awaySince = nil
            refresh(for: owner, help: help)
            return
        }
        // Moving between buttons while a bubble is up swaps it quickly.
        let delay = window.isVisible ? Self.switchDelay : Self.delay
        pending?.cancel()
        self.owner = owner
        let item = DispatchWorkItem { [weak self, weak owner] in
            guard let self, let owner, self.owner === owner else { return }
            self.show(help, for: owner)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// The pointer left `owner`'s button. A bubble that is up stays (the away timer decides when it
    /// goes); one that is still waiting for its pause is cancelled.
    func hoverEnded(for owner: OverlayPanel) {
        guard self.owner === owner else { return }
        if window.isVisible {
            pending?.cancel()
            pending = nil
        } else {
            hide()
        }
    }

    // MARK: Showing and hiding

    /// Swaps the text if the bubble is up for `owner` (the button changed under the pointer).
    func refresh(for owner: OverlayPanel, help: ButtonHelp) {
        guard self.owner === owner, window.isVisible, current != help else { return }
        show(help, for: owner)
    }

    /// Hides the bubble, or, when `owner` is given, only if it belongs to that button.
    func hide(ifOwnedBy owner: OverlayPanel? = nil) {
        if let owner, self.owner !== owner { return }
        pending?.cancel()
        pending = nil
        stopWatching()
        self.owner = nil
        current = nil
        if window.isVisible { window.orderOut(nil) }
        window.contentView = nil
    }

    private func show(_ help: ButtonHelp, for owner: OverlayPanel) {
        let view = HelpBubbleView(help: help)
        window.contentView = view
        window.setContentSize(view.preferredSize)
        window.setFrameOrigin(origin(for: view.preferredSize, below: owner.frame))
        current = help
        awaySince = nil
        startWatching()
        guard !window.isVisible else { return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 1
        }
    }

    // MARK: Watching the pointer

    private func startWatching() {
        guard watcher == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkPointer() }
        RunLoop.main.add(timer, forMode: .common)   // keeps ticking while menus or drags track
        watcher = timer
    }

    private func stopWatching() {
        watcher?.invalidate()
        watcher = nil
        awaySince = nil
    }

    /// Runs ten times a second while the bubble is up: starts the away clock when the pointer is
    /// on neither the bubble nor its button, resets it when the pointer comes back, and hides the
    /// bubble once the pointer has been away for `awayDelay`.
    private func checkPointer() {
        guard window.isVisible else { stopWatching(); return }
        let pointer = pointerLocation()
        let onBubble = window.frame.insetBy(dx: -2, dy: -2).contains(pointer)
        let onButton = owner?.frame.contains(pointer) ?? false
        if onBubble || onButton {
            awaySince = nil
            return
        }
        let now = CACurrentMediaTime()
        if let since = awaySince {
            if now - since >= Self.awayDelay { hide() }
        } else {
            awaySince = now
        }
    }

    /// Just under the button's click area, left edges lined up, kept on the button's screen.
    private func origin(for size: CGSize, below button: CGRect) -> CGPoint {
        var origin = CGPoint(x: button.minX, y: button.minY - size.height - 2)
        let screen = NSScreen.screens.first { $0.frame.intersects(button) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - size.width - 4))
            origin.y = max(visible.minY + 4, origin.y)
        }
        return origin
    }

    #if DEBUG
    var windowNumberForTesting: Int { window.windowNumber }
    var frameForTesting: CGRect { window.frame }
    var isShowingForTesting: Bool { window.isVisible }
    #endif
}
