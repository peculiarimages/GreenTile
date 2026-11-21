import XCTest
@testable import GreenTileKit

final class TileLayoutTests: XCTestCase {
    /// The primary display of the development machine: 2560x1440 with a 31pt menu bar and a Dock
    /// at the bottom, expressed in Accessibility coordinates.
    private let area = CGRect(x: 0, y: 31, width: 2560, height: 1369)

    func testHalves() {
        XCTAssertEqual(TileLayout.leftHalf.frame(in: area), CGRect(x: 0, y: 31, width: 1280, height: 1369))
        XCTAssertEqual(TileLayout.rightHalf.frame(in: area), CGRect(x: 1280, y: 31, width: 1280, height: 1369))
    }

    func testThirds() {
        // 2560 / 3 = 853.33: the edges round to 853 and 1707, so the middle third is 1pt wider.
        XCTAssertEqual(TileLayout.leftThird.frame(in: area), CGRect(x: 0, y: 31, width: 853, height: 1369))
        XCTAssertEqual(TileLayout.centerThird.frame(in: area), CGRect(x: 853, y: 31, width: 854, height: 1369))
        XCTAssertEqual(TileLayout.rightThird.frame(in: area), CGRect(x: 1707, y: 31, width: 853, height: 1369))
    }

    func testNegativeOriginDisplay() {
        let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(TileLayout.leftHalf.frame(in: left), CGRect(x: -2560, y: 0, width: 1280, height: 1440))
        XCTAssertEqual(TileLayout.rightHalf.frame(in: left), CGRect(x: -1280, y: 0, width: 1280, height: 1440))
        XCTAssertEqual(TileLayout.centerThird.frame(in: left).minX, -2560 + 853)
    }

    /// Each mode's tiles must meet exactly and cover the whole area, for awkward sizes too.
    func testEveryModePartitionsTheAreaExactly() {
        let areas = [area,
                     CGRect(x: 3, y: 7, width: 1001, height: 701),
                     CGRect(x: -1, y: 0, width: 1499, height: 900),
                     CGRect(x: 0, y: 0, width: 1501, height: 900)]
        for mode in TileMode.allCases {
            for a in areas {
                let frames = mode.layouts.map { $0.frame(in: a) }
                XCTAssertEqual(frames.first?.minX, a.minX, "\(mode) in \(a)")
                XCTAssertEqual(frames.last?.maxX, a.maxX, "\(mode) in \(a)")
                for (left, right) in zip(frames, frames.dropFirst()) {
                    XCTAssertEqual(left.maxX, right.minX, "\(mode) tiles do not meet in \(a)")
                }
                for f in frames {
                    XCTAssertEqual(f.minY, a.minY)
                    XCTAssertEqual(f.height, a.height)
                }
            }
        }
    }

    func testGapSeparatesTilesAndInsetsTheEdges() {
        let a = CGRect(x: 0, y: 0, width: 1000, height: 500)
        XCTAssertEqual(TileLayout.leftHalf.frame(in: a, gap: 10), CGRect(x: 10, y: 10, width: 485, height: 480))
        XCTAssertEqual(TileLayout.rightHalf.frame(in: a, gap: 10), CGRect(x: 505, y: 10, width: 485, height: 480))
    }

    func testModesAndTheirLayouts() {
        XCTAssertEqual(TileMode.halves.layouts, [.leftHalf, .rightHalf])
        XCTAssertEqual(TileMode.thirds.layouts, [.leftThird, .centerThird, .rightThird])
        XCTAssertEqual(Set(TileLayout.allCases.map(\.title)).count, TileLayout.allCases.count)
    }

    func testVariantsMapToTheSameSide() {
        XCTAssertEqual(TileLayout.leftHalf.thirdVariant, .leftThird)
        XCTAssertEqual(TileLayout.rightHalf.thirdVariant, .rightThird)
        XCTAssertNil(TileLayout.centerThird.thirdVariant)
        XCTAssertNil(TileLayout.leftThird.thirdVariant)
        XCTAssertEqual(TileLayout.leftThird.halfVariant, .leftHalf)
        XCTAssertEqual(TileLayout.rightThird.halfVariant, .rightHalf)
        XCTAssertNil(TileLayout.centerThird.halfVariant)
        XCTAssertNil(TileLayout.leftHalf.halfVariant)
    }

    /// Right-click picks the default mode and Option turns it over.
    func testEffectiveModeIsTheDefaultTurnedOverByOption() {
        XCTAssertEqual(TileMode.effective(thirdsByDefault: false, optionHeld: false), .halves)
        XCTAssertEqual(TileMode.effective(thirdsByDefault: false, optionHeld: true), .thirds)
        XCTAssertEqual(TileMode.effective(thirdsByDefault: true, optionHeld: false), .thirds)
        XCTAssertEqual(TileMode.effective(thirdsByDefault: true, optionHeld: true), .halves)
    }

    func testAdjustedLayoutFollowsTheModeInForce() {
        // A half button clicked while thirds are in force means the third on that side, and back.
        XCTAssertEqual(TileLayout.leftHalf.adjusted(for: .thirds), .leftThird)
        XCTAssertEqual(TileLayout.rightThird.adjusted(for: .halves), .rightHalf)
        // Buttons that already match the mode, or have no counterpart, are left alone.
        XCTAssertEqual(TileLayout.leftHalf.adjusted(for: .halves), .leftHalf)
        XCTAssertEqual(TileLayout.centerThird.adjusted(for: .thirds), .centerThird)
        XCTAssertEqual(TileLayout.centerThird.adjusted(for: .halves), .centerThird)
    }

    func testSlotsMatchTheFrames() {
        XCTAssertEqual(TileLayout.leftHalf.slot, CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(TileLayout.rightHalf.slot, CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(TileLayout.centerThird.slot.width, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(TileLayout.centerThird.slot.minX, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testHalvesSitUnderRedAndGreenAndThirdsUnderAllThree() {
        XCTAssertEqual(TileMode.halves.slots, [TileSlot(layout: .leftHalf, column: 0),
                                               TileSlot(layout: .rightHalf, column: 2)])
        XCTAssertEqual(TileMode.thirds.slots, [TileSlot(layout: .leftThird, column: 0),
                                               TileSlot(layout: .centerThird, column: 1),
                                               TileSlot(layout: .rightThird, column: 2)])
    }

    /// A button keeps its column when Option swaps halves for thirds, so the left and right
    /// buttons stay put and only the middle one appears.
    func testLeftAndRightButtonsKeepTheirColumnAcrossModes() {
        XCTAssertEqual(TileMode.halves.slots.first?.column, TileMode.thirds.slots.first?.column)
        XCTAssertEqual(TileMode.halves.slots.last?.column, TileMode.thirds.slots.last?.column)
    }
}
