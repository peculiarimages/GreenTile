import XCTest
@testable import GreenTileKit

final class ButtonHelpTests: XCTestCase {
    func testTitleAndDetailNameTheRegion() {
        let left = ButtonHelp(for: .leftHalf, thirdsByDefault: false)
        XCTAssertEqual(left.title, "Tile Left Half")
        XCTAssertEqual(left.detail, "Fills the left half of this screen")

        let centre = ButtonHelp(for: .centerThird, thirdsByDefault: true)
        XCTAssertEqual(centre.title, "Tile Center Third")
        XCTAssertEqual(centre.detail, "Fills the center third of this screen")
    }

    func testEveryButtonHasCompleteHelpInBothDefaults() {
        for layout in TileLayout.allCases {
            for thirdsByDefault in [false, true] {
                let help = ButtonHelp(for: layout, thirdsByDefault: thirdsByDefault)
                XCTAssertFalse(help.title.isEmpty)
                XCTAssertTrue(help.detail.contains(layout.region), "\(layout)")
                XCTAssertFalse(help.hint.isEmpty)
            }
        }
        XCTAssertEqual(Set(TileLayout.allCases.map { ButtonHelp(for: $0, thirdsByDefault: false).title }).count,
                       TileLayout.allCases.count)
    }

    /// Normal use: the row on show is the default one, so Option or a right-click gets the other.
    func testHintWhenTheDefaultRowIsShowing() {
        XCTAssertEqual(ButtonHelp(for: .leftHalf, thirdsByDefault: false).hint, "Hold \u{2325} or right-click for thirds")
        XCTAssertEqual(ButtonHelp(for: .rightHalf, thirdsByDefault: false).hint, "Hold \u{2325} or right-click for thirds")
        XCTAssertEqual(ButtonHelp(for: .leftThird, thirdsByDefault: true).hint, "Hold \u{2325} or right-click for halves")
        XCTAssertEqual(ButtonHelp(for: .centerThird, thirdsByDefault: true).hint, "Hold \u{2325} or right-click for halves")
    }

    /// Option held: the row on show is the opposite of the default, so the hint says how to go back.
    func testHintWhileOptionTurnsTheRowOver() {
        XCTAssertEqual(ButtonHelp(for: .leftThird, thirdsByDefault: false).hint, "Release \u{2325} to go back to halves")
        XCTAssertEqual(ButtonHelp(for: .centerThird, thirdsByDefault: false).hint, "Release \u{2325} to go back to halves")
        XCTAssertEqual(ButtonHelp(for: .leftHalf, thirdsByDefault: true).hint, "Release \u{2325} to go back to thirds")
        XCTAssertEqual(ButtonHelp(for: .rightHalf, thirdsByDefault: true).hint, "Release \u{2325} to go back to thirds")
    }

    func testRegionsAndThirds() {
        XCTAssertEqual(TileLayout.allCases.filter(\.isThird).count, 3)
        XCTAssertEqual(Set(TileLayout.allCases.map(\.region)).count, TileLayout.allCases.count)
    }
}
