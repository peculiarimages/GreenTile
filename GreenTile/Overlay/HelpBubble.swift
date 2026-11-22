import AppKit
import GreenTileKit

/// The link row at the foot of every help bubble: the app icon, three times as tall as the round
/// tiling buttons, and the project's address. The whole row is one click target.
final class HelpLinkView: NSView {
    /// The icon is three times as tall as the round tiling buttons.
    static let iconSide = OverlayPlacement.buttonDiameter * 3
    private static let gap: CGFloat = 8
    private static let font = NSFont.systemFont(ofSize: 11)

    /// Called when the row is clicked.
    var onOpen: (() -> Void)?
    private var isHovering = false { didSet { needsDisplay = true } }

    /// Width the row needs: the icon, a gap, and the address.
    static var preferredWidth: CGFloat {
        let text = (ProjectLinks.repository as NSString).size(withAttributes: [.font: font])
        return iconSide + gap + ceil(text.width) + 2
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.link)
        setAccessibilityLabel("Open the GreenTile project page on GitHub")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let iconRect = CGRect(x: 0, y: (bounds.height - Self.iconSide) / 2, width: Self.iconSide, height: Self.iconSide)
        if let icon = NSApp.applicationIconImage {
            // The icon's drawn shape is the middle 824 of its 1024 points; the rest is margin and
            // shadow, so only that middle part is drawn, at exactly `iconSide`.
            let size = icon.size
            let body = CGRect(x: size.width * 100 / 1024, y: size.height * 100 / 1024,
                              width: size.width * 824 / 1024, height: size.height * 824 / 1024)
            icon.draw(in: iconRect, from: body, operation: .sourceOver, fraction: isHovering ? 1 : 0.92,
                      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: isHovering ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .underlineStyle: isHovering ? NSUnderlineStyle.single.rawValue : 0,
        ]
        let text = NSAttributedString(string: ProjectLinks.repository, attributes: attributes)
        text.draw(at: CGPoint(x: iconRect.maxX + Self.gap, y: (bounds.height - text.size().height) / 2))
    }
}

/// A panel over just the link row of the help bubble. It takes mouse clicks (the bubble itself
/// ignores them, so it never blocks the window beneath) and never takes focus.
final class HelpLinkPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The contents of the help bubble: a bold name, what a click does, a quieter hint line, and, after
/// two blank lines, room for the link row.
final class HelpBubbleView: NSVisualEffectView {
    private(set) var preferredSize: CGSize = .zero
    /// Where the link row goes, in this view's coordinates (y up).
    private(set) var footerRect: CGRect = .zero
    /// The last line of text, in this view's coordinates.
    private(set) var lastTextFrame: CGRect = .zero

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
        let lineHeight = labels[2].intrinsicContentSize.height
        let blankLines: CGFloat = 2
        let linkGap = blankLines * lineHeight
        let footerHeight = HelpLinkView.iconSide
        let textWidth = max(labels.map { $0.intrinsicContentSize.width }.max() ?? 0, HelpLinkView.preferredWidth)
        let textHeight = labels.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.height } + spacing * CGFloat(labels.count - 1)
        // A few points of slack: a text field clips its last glyph if its frame is exactly as wide as
        // the measured text.
        let size = CGSize(width: ceil(textWidth) + 2 * padX + 6,
                          height: ceil(textHeight) + linkGap + footerHeight + 2 * padY)
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
        lastTextFrame = labels[2].frame
        // The text fields draw their glyphs 2 pt in from their frames: line the link row up with them.
        footerRect = CGRect(x: padX + 2, y: padY, width: size.width - 2 * padX - 2, height: footerHeight)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The clickable row that goes over `footerRect` (in its own panel; see `HelpLinkPanel`).
    func makeLinkView() -> HelpLinkView {
        HelpLinkView(frame: CGRect(origin: .zero, size: footerRect.size))
    }

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
    /// Pause before the bubble first appears: a full second, so passing over a button on the way
    /// somewhere else doesn't bring it up.
    static let delay: TimeInterval = 1
    /// Pause when moving from one button to the next while a bubble is already up.
    static let switchDelay: TimeInterval = 0.12
    /// How long the pointer may stay away from both the bubble and its button before it hides.
    static let awayDelay: TimeInterval = 2

    private let window: NSPanel
    /// The clickable link row over the foot of the bubble.
    private let linkPanel = HelpLinkPanel()
    private var pending: DispatchWorkItem?
    private var watcher: Timer?
    private var awaySince: CFTimeInterval?
    /// The button panel the bubble is for, from when it is scheduled until it is hidden.
    private weak var owner: ButtonPanel?
    /// The text on show, for the self-test.
    private(set) var current: ButtonHelp?

    /// Where the pointer is, in screen coordinates. Replaced only by the self-test.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    /// Opens an address in the default browser. Replaced only by the self-test.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Whether `other` is one of the bubble's own windows (a click on the link row must not count as
    /// a click elsewhere that dismisses the bubble).
    func ownsWindow(_ other: NSWindow?) -> Bool {
        guard let other else { return false }
        return other === window || other === linkPanel
    }

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
    func hoverBegan(for owner: ButtonPanel, help: ButtonHelp) {
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
    func hoverEnded(for owner: ButtonPanel) {
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
    func refresh(for owner: ButtonPanel, help: ButtonHelp) {
        guard self.owner === owner, window.isVisible, current != help else { return }
        show(help, for: owner)
    }

    /// Hides the bubble, or, when `owner` is given, only if it belongs to that button.
    func hide(ifOwnedBy owner: ButtonPanel? = nil) {
        if let owner, self.owner !== owner { return }
        pending?.cancel()
        pending = nil
        stopWatching()
        self.owner = nil
        current = nil
        window.removeChildWindow(linkPanel)
        linkPanel.orderOut(nil)
        linkPanel.contentView = nil
        if window.isVisible { window.orderOut(nil) }
        window.contentView = nil
    }

    /// Opens the project page and puts the bubble away. (The bubble goes on the next turn of the
    /// run loop: this is called from the link row's own click handler.)
    private func openRepository() {
        if let url = URL(string: ProjectLinks.repository) { openURL(url) }
        DispatchQueue.main.async { [weak self] in self?.hide() }
    }

    /// Puts the clickable link row over the foot of the bubble, as a child window so the two move
    /// and hide together.
    private func placeLinkRow(for view: HelpBubbleView) {
        let link = view.makeLinkView()
        link.onOpen = { [weak self] in self?.openRepository() }
        linkPanel.contentView = link
        let origin = window.frame.origin
        linkPanel.setFrame(CGRect(x: origin.x + view.footerRect.minX, y: origin.y + view.footerRect.minY,
                                  width: view.footerRect.width, height: view.footerRect.height), display: false)
        if linkPanel.parent == nil { window.addChildWindow(linkPanel, ordered: .above) }
    }

    private func show(_ help: ButtonHelp, for owner: ButtonPanel) {
        let view = HelpBubbleView(help: help)
        window.contentView = view
        window.setContentSize(view.preferredSize)
        window.setFrameOrigin(origin(for: view.preferredSize, below: owner.frame))
        current = help
        awaySince = nil
        startWatching()
        let wasVisible = window.isVisible
        if !wasVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        placeLinkRow(for: view)
        guard !wasVisible else { return }
        linkPanel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 1
            linkPanel.animator().alphaValue = 1
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
    var linkPanelFrameForTesting: CGRect { linkPanel.frame }
    var linkPanelWindowNumberForTesting: Int { linkPanel.windowNumber }
    var isLinkRowShowingForTesting: Bool { linkPanel.isVisible }
    var bubbleIgnoresMouseEventsForTesting: Bool { window.ignoresMouseEvents }
    var linkRowAcceptsMouseEventsForTesting: Bool { !linkPanel.ignoresMouseEvents }
    #endif
}
