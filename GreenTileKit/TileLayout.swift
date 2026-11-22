import CoreGraphics

/// The window arrangements offered next to the green button. Every layout spans the full height
/// of the display's usable area and takes one column of an equal-width grid.
public enum TileLayout: String, CaseIterable, Sendable {
    case leftHalf, rightHalf
    case leftThird, centerThird, rightThird

    /// Which column of how many this layout occupies.
    private var grid: (column: Int, columns: Int) {
        switch self {
        case .leftHalf: return (0, 2)
        case .rightHalf: return (1, 2)
        case .leftThird: return (0, 3)
        case .centerThird: return (1, 3)
        case .rightThird: return (2, 3)
        }
    }

    public var title: String {
        switch self {
        case .leftHalf: return "Tile Left Half"
        case .rightHalf: return "Tile Right Half"
        case .leftThird: return "Tile Left Third"
        case .centerThird: return "Tile Center Third"
        case .rightThird: return "Tile Right Third"
        }
    }

    /// The part of the screen this layout fills, in words.
    public var region: String {
        switch self {
        case .leftHalf: return "left half"
        case .rightHalf: return "right half"
        case .leftThird: return "left third"
        case .centerThird: return "center third"
        case .rightThird: return "right third"
        }
    }

    public var isThird: Bool { grid.columns == 3 }

    /// The tile in unit space (0...1, origin top-left, y grows downward, matching Accessibility
    /// coordinates). Used to draw the icon.
    public var slot: CGRect {
        let g = grid
        return CGRect(x: CGFloat(g.column) / CGFloat(g.columns), y: 0, width: 1 / CGFloat(g.columns), height: 1)
    }

    /// The same side in thirds (left half -> left third), if there is one.
    public var thirdVariant: TileLayout? {
        switch self {
        case .leftHalf: return .leftThird
        case .rightHalf: return .rightThird
        default: return nil
        }
    }

    /// The same side in halves (left third -> left half), if there is one. The center third has none.
    public var halfVariant: TileLayout? {
        switch self {
        case .leftThird: return .leftHalf
        case .rightThird: return .rightHalf
        default: return nil
        }
    }

    /// What a click on this button should do when `mode` is the one the user means. A button can
    /// still be showing the previous mode for a moment after Option is pressed or released, so the
    /// click is judged by the mode in force at click time rather than by what was drawn.
    public func adjusted(for mode: TileMode) -> TileLayout {
        switch mode {
        case .halves: return halfVariant ?? self
        case .thirds: return thirdVariant ?? self
        }
    }

    /// The window frame for `area`. Every column edge is computed from the same expression by both
    /// neighbours and rounded to whole points, so tiles always meet exactly: no overlap, no
    /// hairline gap, whatever the width. `gap` is the spacing between tiles and also the margin to
    /// the area's edge.
    public func frame(in area: CGRect, gap: CGFloat = 0) -> CGRect {
        let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
        let (column, columns) = grid
        func edge(_ k: Int) -> CGFloat {
            (inner.minX + inner.width * CGFloat(k) / CGFloat(columns)).rounded()
        }
        let x0 = edge(column), x1 = edge(column + 1)
        let y0 = inner.minY.rounded(), y1 = inner.maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            .insetBy(dx: gap / 2, dy: gap / 2)
    }
}

/// One button: what it tiles to, and which traffic light it sits under.
public struct TileSlot: Equatable, Sendable {
    public let layout: TileLayout
    /// 0 = under the red button, 1 = under the yellow one, 2 = under the green one.
    public let column: Int

    public init(layout: TileLayout, column: Int) {
        self.layout = layout
        self.column = column
    }
}

/// Which set of buttons is showing: two halves normally, three thirds while Option is held.
public enum TileMode: CaseIterable, Sendable {
    case halves, thirds

    /// The halves sit under the red and green buttons (the yellow one is left clear); the thirds
    /// sit under all three.
    public var slots: [TileSlot] {
        switch self {
        case .halves:
            return [TileSlot(layout: .leftHalf, column: 0), TileSlot(layout: .rightHalf, column: 2)]
        case .thirds:
            return [TileSlot(layout: .leftThird, column: 0),
                    TileSlot(layout: .centerThird, column: 1),
                    TileSlot(layout: .rightThird, column: 2)]
        }
    }

    public var layouts: [TileLayout] { slots.map(\.layout) }

    /// The mode in force: halves or thirds as chosen with a right-click (`thirdsByDefault`), turned
    /// over while Option is held.
    public static func effective(thirdsByDefault: Bool, optionHeld: Bool) -> TileMode {
        thirdsByDefault != optionHeld ? .thirds : .halves
    }
}

extension TileLayout {
    /// The layout `frame` is tiled to in `area`, if any. Windows do not always land exactly on the
    /// tile: some apps size in steps (a terminal's character cells) or have a minimum size. So the
    /// position may be off by `positionTolerance` points and the size by `sizeTolerance`, and of
    /// several layouts within those limits the closest wins.
    public static func matching(_ frame: CGRect, in area: CGRect, gap: CGFloat = 0,
                                positionTolerance: CGFloat = 2, sizeTolerance: CGFloat = 16) -> TileLayout? {
        var best: (layout: TileLayout, distance: CGFloat)?
        for layout in allCases {
            let tile = layout.frame(in: area, gap: gap)
            let dx = abs(frame.minX - tile.minX), dy = abs(frame.minY - tile.minY)
            let dw = abs(frame.width - tile.width), dh = abs(frame.height - tile.height)
            guard dx <= positionTolerance, dy <= positionTolerance,
                  dw <= sizeTolerance, dh <= sizeTolerance else { continue }
            let distance = dx + dy + dw + dh
            if best == nil || distance < best!.distance { best = (layout, distance) }
        }
        return best?.layout
    }
}
