import XCTest
@testable import GreenTileKit

final class DisplayNeighbourTests: XCTestCase {
    // The development machine: a Dell (primary) with a Thunderbolt Display to its left.
    private let dell = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let thunderbolt = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    func testSideBySideDisplaysAreEachOthersNeighbours() {
        let frames = [dell, thunderbolt]
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: frames), 1)
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .right, in: frames))
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 1, on: .right, in: frames), 0)
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 1, on: .left, in: frames))
    }

    func testSingleDisplayHasNoNeighbours() {
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: [dell]))
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .right, in: [dell]))
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 5, on: .left, in: [dell]))   // out of range
    }

    func testStackedDisplaysAreNotLeftOrRightNeighbours() {
        let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: [dell, above]))
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .right, in: [dell, above]))
    }

    /// A display that only touches at a corner shares no edge with this one.
    func testCornerContactDoesNotCount() {
        let diagonal = CGRect(x: 2560, y: 1440, width: 1920, height: 1080)
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .right, in: [dell, diagonal]))
    }

    func testOffsetDisplaysStillCountWhileTheyShareSomeHeight() {
        let lower = CGRect(x: 2560, y: 500, width: 1920, height: 1080)   // shares 940 pt of height
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 0, on: .right, in: [dell, lower]), 1)
    }

    func testAChainOfDisplaysOnlyOffersTheAdjacentOne() {
        let far = CGRect(x: -5120, y: 0, width: 2560, height: 1440)
        let frames = [dell, thunderbolt, far]
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: frames), 1)   // not the far one
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 1, on: .left, in: frames), 2)
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 2, on: .right, in: frames), 1)
    }

    func testTheNeighbourBesideTheWindowWins() {
        // Two displays stacked on the left of the primary display.
        let upperLeft = CGRect(x: -2560, y: 0, width: 2560, height: 720)
        let lowerLeft = CGRect(x: -2560, y: 720, width: 2560, height: 720)
        let frames = [dell, upperLeft, lowerLeft]
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: frames,
                                                     preferring: CGRect(x: 100, y: 100, width: 800, height: 400)), 1)
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: frames,
                                                     preferring: CGRect(x: 100, y: 900, width: 800, height: 400)), 2)
    }

    func testSmallGapsAreToleratedButWideOnesAreNot() {
        XCTAssertEqual(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: [dell, thunderbolt.offsetBy(dx: -1, dy: 0)]), 1)
        XCTAssertNil(ScreenGeometry.neighbourIndex(of: 0, on: .left, in: [dell, thunderbolt.offsetBy(dx: -5, dy: 0)]))
    }
}

final class ProportionalMoveTests: XCTestCase {
    private let dellUsable = CGRect(x: 0, y: 31, width: 2560, height: 1369)
    private let thunderboltUsable = CGRect(x: -2560, y: 31, width: 2560, height: 1409)

    func testATiledHalfStaysTheSameHalfOnTheOtherDisplay() {
        let leftHalf = TileLayout.leftHalf.frame(in: dellUsable)
        XCTAssertEqual(ScreenGeometry.mapProportionally(leftHalf, from: dellUsable, to: thunderboltUsable),
                       TileLayout.leftHalf.frame(in: thunderboltUsable))
        let rightThird = TileLayout.rightThird.frame(in: dellUsable)
        XCTAssertEqual(ScreenGeometry.mapProportionally(rightThird, from: dellUsable, to: thunderboltUsable),
                       TileLayout.rightThird.frame(in: thunderboltUsable))
    }

    func testAWindowKeepsItsShareOfADifferentlySizedDisplay() {
        let small = CGRect(x: 2560, y: 25, width: 1920, height: 1055)
        let half = TileLayout.rightHalf.frame(in: dellUsable)
        XCTAssertEqual(ScreenGeometry.mapProportionally(half, from: dellUsable, to: small),
                       TileLayout.rightHalf.frame(in: small))
    }

    func testAFreeFloatingWindowKeepsItsRelativePosition() {
        let window = CGRect(x: 256, y: 200, width: 1280, height: 800)
        let moved = ScreenGeometry.mapProportionally(window, from: dellUsable, to: thunderboltUsable)
        XCTAssertEqual(moved.minX - thunderboltUsable.minX, window.minX - dellUsable.minX, accuracy: 1)
        XCTAssertEqual(moved.width, 1280, accuracy: 1)   // same-sized displays: same size
        XCTAssertTrue(thunderboltUsable.contains(moved))
    }

    func testTheResultNeverLeavesTheDestination() {
        // Hanging off the left and bottom of the source display.
        let sprawling = CGRect(x: -300, y: 1000, width: 3200, height: 900)
        let moved = ScreenGeometry.mapProportionally(sprawling, from: dellUsable, to: thunderboltUsable)
        XCTAssertTrue(thunderboltUsable.contains(moved), "\(moved)")
    }

    func testEdgesAreWholePoints() {
        let odd = CGRect(x: 100.4, y: 80.6, width: 999.3, height: 500.1)
        let moved = ScreenGeometry.mapProportionally(odd, from: dellUsable, to: CGRect(x: 0, y: 0, width: 1711, height: 983))
        for v in [moved.minX, moved.minY, moved.maxX, moved.maxY] { XCTAssertEqual(v, v.rounded()) }
    }
}

final class ChevronPlacementTests: XCTestCase {
    /// A typical window at the origin with its traffic lights 16 pt in and 14 pt down.
    private let window = CGRect(x: 0, y: 0, width: 900, height: 600)
    private let lights = CGRect(x: 16, y: 14, width: 62, height: 16)

    func testChevronsSitInTheSameRowAsTheTileButtons() {
        let tile = OverlayPlacement.frame(column: 0, trafficLights: lights)
        for side in [DisplaySide.left, .right] {
            let chevron = OverlayPlacement.chevronFrame(side: side, trafficLights: lights, windowFrame: window)
            XCTAssertEqual(chevron?.minY, tile.minY)
            XCTAssertEqual(chevron?.height, tile.height)
        }
    }

    func testRightChevronTouchesTheRightmostTileButtonAndHasFullSize() {
        let tileRight = OverlayPlacement.frame(column: 2, trafficLights: lights)
        let chevron = OverlayPlacement.chevronFrame(side: .right, trafficLights: lights, windowFrame: window)
        XCTAssertEqual(chevron?.minX, tileRight.maxX)
        XCTAssertEqual(chevron?.width, OverlayPlacement.hitSize)
    }

    func testLeftChevronTouchesTheLeftmostTileButtonAndStaysOffTheWindowEdge() {
        let tileLeft = OverlayPlacement.frame(column: 0, trafficLights: lights)
        let chevron = OverlayPlacement.chevronFrame(side: .left, trafficLights: lights, windowFrame: window)
        XCTAssertEqual(chevron?.maxX, tileLeft.minX)
        // Only 16 pt are free left of the lights, minus the margin kept from the window's edge.
        XCTAssertEqual(chevron?.minX, OverlayPlacement.chevronEdgeInset)
        XCTAssertEqual(chevron?.width, 16 - OverlayPlacement.chevronEdgeInset)
    }

    func testChevronsNeverOverlapTheTileButtonsOrTheLights() {
        let tiles = (0...2).map { OverlayPlacement.frame(column: $0, trafficLights: lights) }
        for side in [DisplaySide.left, .right] {
            guard let chevron = OverlayPlacement.chevronFrame(side: side, trafficLights: lights, windowFrame: window) else {
                return XCTFail("no chevron for \(side)")
            }
            XCTAssertFalse(chevron.intersects(lights))
            for tile in tiles { XCTAssertFalse(chevron.intersects(tile), "\(side) chevron overlaps a tile button") }
        }
    }

    func testLeftChevronIsDroppedOnlyWhenThereIsReallyNoRoom() {
        let none = CGRect(x: 6, y: 14, width: 62, height: 16)     // only 6 pt left of the lights
        XCTAssertNil(OverlayPlacement.chevronFrame(side: .left, trafficLights: none, windowFrame: window))
        let enough = CGRect(x: 12, y: 14, width: 62, height: 16)  // 12 - 3 = 9 pt of room
        XCTAssertNotNil(OverlayPlacement.chevronFrame(side: .left, trafficLights: enough, windowFrame: window))
    }

    /// A plain AppKit window has its traffic lights only 8 pt from the edge: the chevron then uses
    /// the whole gap instead of keeping its usual margin from the window's edge.
    func testTightWindowsGetANarrowerLeftChevronThatStillFitsInsideTheWindow() {
        let tight = CGRect(x: 8, y: 14, width: 62, height: 16)
        let chevron = OverlayPlacement.chevronFrame(side: .left, trafficLights: tight, windowFrame: window)
        XCTAssertEqual(chevron?.minX, 0)
        XCTAssertEqual(chevron?.width, 8)
        XCTAssertEqual(chevron?.maxX, 8)   // still touches the leftmost tile button
    }

    func testRightChevronIsTrimmedToTheWindow() {
        let narrow = CGRect(x: 0, y: 0, width: 90, height: 600)   // lights end at 78: 12 pt of room
        let chevron = OverlayPlacement.chevronFrame(side: .right, trafficLights: lights, windowFrame: narrow)
        XCTAssertEqual(chevron?.maxX, 90)
        XCTAssertEqual(chevron?.width, 12)
    }

    func testChevronsFollowAWindowOnAnotherDisplay() {
        let farWindow = window.offsetBy(dx: -2560, dy: 31)
        let farLights = lights.offsetBy(dx: -2560, dy: 31)
        let near = OverlayPlacement.chevronFrame(side: .right, trafficLights: lights, windowFrame: window)!
        let far = OverlayPlacement.chevronFrame(side: .right, trafficLights: farLights, windowFrame: farWindow)!
        XCTAssertEqual(far.minX - near.minX, -2560)
        XCTAssertEqual(far.minY - near.minY, 31)
    }

    func testHelpNamesTheNeighbouringDisplay() {
        let left = ButtonHelp(movingToDisplayNamed: "Thunderbolt Display", side: .left)
        XCTAssertEqual(left.title, "Move to Left Display")
        XCTAssertEqual(left.detail, "Sends this window to Thunderbolt Display")
        XCTAssertFalse(left.hint.isEmpty)
        XCTAssertEqual(ButtonHelp(movingToDisplayNamed: "DELL U2718Q", side: .right).title, "Move to Right Display")
    }
}
