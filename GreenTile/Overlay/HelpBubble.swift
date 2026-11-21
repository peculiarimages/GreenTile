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
final class HelpBubble {
    private let window: NSPanel
    private var pending: DispatchWorkItem?
    /// The button panel the bubble is for, from when it is scheduled until it is hidden.
    private weak var owner: OverlayPanel?
    /// The text on show, for the self-test.
    private(set) var current: ButtonHelp?

    /// Matches the pause before a standard tooltip appears.
    static let delay: TimeInterval = 0.45

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

    /// Shows `help` for `owner` after `delay`. A later call replaces an earlier one.
    func schedule(for owner: OverlayPanel, help: ButtonHelp, delay: TimeInterval = HelpBubble.delay) {
        hide()
        self.owner = owner
        let item = DispatchWorkItem { [weak self, weak owner] in
            guard let self, let owner, self.owner === owner else { return }
            self.show(help, for: owner)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

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
        guard !window.isVisible else { return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 1
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
    #endif
}
