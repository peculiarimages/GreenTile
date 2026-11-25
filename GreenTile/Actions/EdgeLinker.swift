import AppKit
import ApplicationServices
import GreenTileKit

/// Resizes two side-by-side windows together: hold ⌘ while dragging the vertical edge one window
/// shares with another, and the other window's edge follows, so the border between them moves as
/// one (one gets wider, the other narrower, no gap and no overlap).
///
/// Driven by the overlay's window poll. A window whose frame changes by one vertical edge only,
/// while the left mouse button and ⌘ are held, is being resized; the window whose edge touched
/// that edge before the drag is its neighbour, and is resized to meet it on every poll until the
/// button is let go. An app's minimum width is respected: the neighbour is never pushed narrower
/// than its app allows, and on release the dragged window is trimmed back to meet it. Both windows
/// then keep the new split as their tile, so Stage Manager snap-back keeps it too. A neighbour
/// hidden behind another window is brought up to just below the dragged one when the drag starts.
final class EdgeLinker {
    private struct Link {
        let dragged: CGWindowID
        let draggedElement: AXUIElement
        /// The edge of the dragged window that is moving.
        let edge: VerticalEdge
        let neighbour: CGWindowID
        let neighbourElement: AXUIElement
        /// The neighbour's far edge, which stays where it is.
        let outer: CGFloat
        var border: CGFloat
    }

    private var previous: [CGWindowID: CGRect] = [:]
    private var link: Link?

    /// Call on every poll with the ordinary windows on screen, front to back, before the Stage
    /// Manager snapper. `linkHeld` is whether ⌘ is down.
    /// - Returns: whether a linked resize is in progress or just finished (poll fast).
    @discardableResult
    func update(windows: [WindowCatalog.Info], element: (CGWindowID) -> AXUIElement?,
                displays: [Display], linkHeld: Bool) -> Bool {
        let bounds = Dictionary(windows.map { ($0.id, $0.bounds) }, uniquingKeysWith: { a, _ in a })
        defer { previous = bounds }
        let leftDown = NSEvent.pressedMouseButtons & 1 != 0

        if var active = link {
            guard let frame = bounds[active.dragged] else { link = nil; return false }
            let border = active.edge == .right ? frame.maxX : frame.minX
            if leftDown {
                if border != active.border {
                    active.border = border
                    link = active
                    follow(active, draggedFrame: frame)
                }
                return true
            }
            active.border = border
            finish(active, draggedFrame: frame, displays: displays)
            link = nil
            return true
        }

        guard leftDown, linkHeld else { return false }
        for window in windows {
            guard let before = previous[window.id], before != window.bounds,
                  let edge = LinkedEdge.resizedEdge(from: before, to: window.bounds) else { continue }
            // The neighbour touched the edge where it was before the drag, on the same display.
            let frames = displays.map(\.frame)
            let display = ScreenGeometry.areaIndex(for: before, in: frames)
            let others = windows.filter {
                $0.id != window.id && ScreenGeometry.areaIndex(for: $0.bounds, in: frames) == display
            }
            guard let found = LinkedEdge.neighbour(of: before, edge: edge, in: others.map(\.bounds)),
                  let draggedElement = element(window.id),
                  let neighbourElement = element(others[found].id) else { return false }
            let neighbourFrame = others[found].bounds
            let active = Link(dragged: window.id, draggedElement: draggedElement, edge: edge,
                              neighbour: others[found].id, neighbourElement: neighbourElement,
                              outer: edge == .right ? neighbourFrame.maxX : neighbourFrame.minX,
                              border: edge == .right ? window.bounds.maxX : window.bounds.minX)
            link = active
            reveal(active, in: windows)
            follow(active, draggedFrame: window.bounds)
            return true
        }
        return false
    }

    /// When a window other than the one being dragged sits in front of the neighbour over the space
    /// the two share (a second window on the dragged window's side, say, which would hide the
    /// neighbour as it grows), brings the neighbour up to just below the dragged window, so its edge
    /// can be seen following. Neither app is activated.
    private func reveal(_ link: Link, in windows: [WindowCatalog.Info]) {
        let frames = windows.map(\.bounds)
        guard let neighbour = windows.firstIndex(where: { $0.id == link.neighbour }),
              let dragged = windows.firstIndex(where: { $0.id == link.dragged }),
              LinkedEdge.neighbourIsHidden(neighbour, dragged: dragged, in: frames) else { return }
        AX.raiseWithoutActivating(link.neighbourElement)
        AX.raiseWithoutActivating(link.draggedElement)
    }

    /// Moves the neighbour's near edge to the border. If its app will not let it get that narrow,
    /// it keeps its far edge where it was and overlaps until the button is let go.
    @discardableResult
    private func follow(_ link: Link, draggedFrame: CGRect) -> CGRect? {
        guard let current = AX.frame(of: link.neighbourElement) else { return nil }
        let target = LinkedEdge.neighbourFrame(border: link.border, outer: link.outer,
                                               side: link.edge, keeping: current)
        AX.setFrame(link.neighbourElement, to: target)
        guard let actual = AX.frame(of: link.neighbourElement) else { return nil }
        guard actual.width > target.width + 1 else { return actual }
        // Too narrow for the app: keep the far edge in place instead of running off the display.
        let x = link.edge == .right ? link.outer - actual.width : link.outer
        AX.setPosition(link.neighbourElement, CGPoint(x: x, y: actual.minY))
        return AX.frame(of: link.neighbourElement)
    }

    /// Lines both windows up exactly on release and remembers the split as their tiles.
    private func finish(_ link: Link, draggedFrame: CGRect, displays: [Display]) {
        guard var neighbour = follow(link, draggedFrame: draggedFrame),
              var dragged = AX.frame(of: link.draggedElement) else { return }
        // The neighbour stopped at its minimum width: bring the dragged window's edge back to it.
        let meet = link.edge == .right ? neighbour.minX : neighbour.maxX
        let draggedEdge = link.edge == .right ? dragged.maxX : dragged.minX
        if abs(meet - draggedEdge) > 1 {
            let x0 = link.edge == .right ? dragged.minX : meet
            let x1 = link.edge == .right ? meet : dragged.maxX
            AX.setFrame(link.draggedElement, to: CGRect(x: x0, y: dragged.minY, width: x1 - x0, height: dragged.height))
            dragged = AX.frame(of: link.draggedElement) ?? dragged
            // The dragged window has a minimum width too: if it would not shrink, the neighbour
            // gives way instead.
            let draggedNow = link.edge == .right ? dragged.maxX : dragged.minX
            if abs(draggedNow - meet) > 1 {
                var again = link
                again.border = draggedNow
                neighbour = follow(again, draggedFrame: dragged) ?? neighbour
            }
        }
        let frames = displays.map(\.frame)
        for (id, frame) in [(link.dragged, dragged), (link.neighbour, neighbour)] {
            guard let index = ScreenGeometry.areaIndex(for: frame, in: frames) else { continue }
            let area = displays[index].usable
            let tile = TileLayout.matching(frame, in: area, gap: WindowActions.tileGap).map(Tile.layout)
                ?? Tile.fitting(frame, in: area)
            WindowActions.remember(id, as: tile, at: frame)
        }
    }
}
