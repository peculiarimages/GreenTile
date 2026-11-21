/// The help shown when the pointer rests on a button: what it is, what it does, and how to switch
/// between halves and thirds. Kept free of any UI so the wording can be tested.
public struct ButtonHelp: Equatable, Sendable {
    /// The button's name, e.g. "Tile Left Half".
    public let title: String
    /// What a click does.
    public let detail: String
    /// How to get the other row of buttons, which depends on what is showing and why.
    public let hint: String

    /// Help for the chevron that sends a window to the display beside this one.
    /// - Parameters:
    ///   - name: the neighbouring display's name, e.g. "Thunderbolt Display".
    ///   - side: which side that display is on.
    public init(movingToDisplayNamed name: String, side: DisplaySide) {
        title = side == .left ? "Move to Left Display" : "Move to Right Display"
        detail = "Sends this window to \(name)"
        hint = "Keeps its size and place in proportion"
    }

    /// - Parameters:
    ///   - layout: the button's layout.
    ///   - thirdsByDefault: whether thirds are the default row (chosen with a right-click).
    public init(for layout: TileLayout, thirdsByDefault: Bool) {
        title = layout.title
        detail = "Fills the \(layout.region) of this screen"

        // Option turns the default row over, so it is being held exactly when the row on show
        // (the one this button belongs to) differs from the default.
        let optionHeld = layout.isThird != thirdsByDefault
        if optionHeld {
            hint = "Release \u{2325} to go back to \(thirdsByDefault ? "thirds" : "halves")"
        } else {
            hint = "Hold \u{2325} or right-click for \(layout.isThird ? "halves" : "thirds")"
        }
    }
}
