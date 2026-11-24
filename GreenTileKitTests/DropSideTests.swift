import XCTest
@testable import GreenTileKit

/// A window dragged in from Stage Manager's strip takes the side it is dropped on.
final class DropSideTests: XCTestCase {
    let area = CGRect(x: 0, y: 31, width: 2400, height: 1369)

    func testHalvesFollowTheDropHalf() {
        XCTAssertEqual(TileLayout.leftHalf.dropped(atX: 1800, in: area), .rightHalf)
        XCTAssertEqual(TileLayout.leftHalf.dropped(atX: 300, in: area), .leftHalf)
        XCTAssertEqual(TileLayout.rightHalf.dropped(atX: 1199, in: area), .leftHalf)
        XCTAssertEqual(TileLayout.rightHalf.dropped(atX: 1200, in: area), .rightHalf)
    }

    func testThirdsFollowTheDropThird() {
        XCTAssertEqual(TileLayout.rightThird.dropped(atX: 100, in: area), .leftThird)
        XCTAssertEqual(TileLayout.leftThird.dropped(atX: 1200, in: area), .centerThird)
        XCTAssertEqual(TileLayout.centerThird.dropped(atX: 2300, in: area), .rightThird)
    }

    func testDropOffTheAreaClampsToTheNearestTile() {
        XCTAssertEqual(TileLayout.rightHalf.dropped(atX: -50, in: area), .leftHalf)
        XCTAssertEqual(TileLayout.leftThird.dropped(atX: 5000, in: area), .rightThird)
    }

    func testSecondDisplay() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(TileLayout.leftHalf.dropped(atX: -200, in: left), .rightHalf)
        XCTAssertEqual(TileLayout.rightThird.dropped(atX: -960, in: left), .centerThird)
    }
}
