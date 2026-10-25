// Tests/Layout/StackSolverTests.swift
/*
 Tests for StackSolver, SwiftUI's stack arithmetic: least flexible children are offered space
 first, each the space left divided by the children left; what one does not take goes to the
 rest; spacing comes off first; minimums can overflow. Cases from the published measurements of
 SwiftUI's HStack (objc.io, "HStacks: Child Ordering", 2020) included. No display needed.
*/

import XCTest
@testable import ActionUI

final class StackSolverTests: XCTestCase {

    private func sizes(_ children: [StackChild], _ available: Int, spacing: Int = 0) -> [Int] {
        StackSolver.mainSizes(children, available: available, spacing: spacing)
    }

    func testExpandingChildrenShareEquallyWhateverTheirMinimums() {
        // Not natural size plus an equal share of the rest: an equal share each.
        XCTAssertEqual(sizes([.expanding(minimum: 10), .expanding(minimum: 50)], 200), [100, 100])
    }

    func testAFixedChildIsServedFirstAndTheRestGoesToTheFlexibleOne() {
        XCTAssertEqual(sizes([.expanding(minimum: 0), .fixed(minimum: 0, natural: 40)], 200), [160, 40])
    }

    func testSpaceACappedChildDoesNotTakeGoesToTheOthers() {
        // The capped child is less flexible, so it is offered 150 first and takes 50.
        XCTAssertEqual(sizes([.expanding(minimum: 0), .expanding(minimum: 0, cap: 50)], 300), [250, 50])
    }

    func testTheObjcIOMeasurement() {
        // A maxWidth-100 child and a minWidth-100 child in 150: the first is offered 75 and takes
        // it, the second is offered 75 and takes its 100; the stack overflows to 175.
        let result = sizes([.expanding(minimum: 0, cap: 100), .expanding(minimum: 100)], 150)
        XCTAssertEqual(result, [75, 100])
        XCTAssertEqual(StackSolver.length(of: result, spacing: 0), 175)
    }

    func testTheLessFlexibleOfTwoRangesGoesFirst() {
        // The objc.io case that ordering by flexibility explains: 0...100 (range 100) before
        // 90...200 (range 110), so the second gets only its minimum.
        XCTAssertEqual(sizes([.expanding(minimum: 0, cap: 100), .expanding(minimum: 90, cap: 200)], 150), [75, 90])
    }

    func testSpacingComesOffFirst() {
        let three = Array(repeating: StackChild.expanding(minimum: 0), count: 3)
        XCTAssertEqual(sizes(three, 320, spacing: 10), [100, 100, 100])
        XCTAssertEqual(StackSolver.length(of: [100, 100, 100], spacing: 10), 320)
    }

    func testEqualChildrenGoInOrderAndTheLastTakesTheRemainder() {
        let three = Array(repeating: StackChild.expanding(minimum: 0), count: 3)
        XCTAssertEqual(sizes(three, 100), [33, 33, 34])
    }

    func testWithoutRoomChildrenShrinkToEqualSharesNotBelowTheirMinimums() {
        XCTAssertEqual(sizes([.fixed(minimum: 20, natural: 100), .fixed(minimum: 20, natural: 100)], 100), [50, 50])
        XCTAssertEqual(sizes([.fixed(minimum: 80, natural: 100), .fixed(minimum: 80, natural: 100)], 100), [80, 80])
    }

    func testFixedChildrenWithRoomTakeTheirNaturalSizes() {
        XCTAssertEqual(sizes([.fixed(minimum: 0, natural: 30), .fixed(minimum: 0, natural: 70)], 500), [30, 70])
    }

    func testBoundedChildrenGivenRoomForAllTheirLargestSizesTakeThem() {
        // SwiftUI's shares of 95 would offer the first 47 and leave it short; GTK gives such a
        // stack no more than this sum where SwiftUI's parent usually proposes more.
        let two: [StackChild] = [.expanding(minimum: 38, cap: 51), .expanding(minimum: 31, cap: 44)]
        XCTAssertEqual(sizes(two, 107, spacing: 12), [51, 44])
        // One short of the sum: SwiftUI's shares, the first offered 47.
        XCTAssertEqual(sizes(two, 106, spacing: 12), [47, 44])
    }

    func testACapBelowTheMinimumKeepsTheMinimum() {
        XCTAssertEqual(StackChild.expanding(minimum: 40, cap: 10).size(offered: 100), 40)
        XCTAssertEqual(StackChild.fixed(minimum: 40, natural: 10).size(offered: 100), 40)
    }

    func testNoChildren() {
        XCTAssertEqual(sizes([], 100), [])
        XCTAssertEqual(StackSolver.length(of: [], spacing: 10), 0)
        XCTAssertEqual(StackSolver.gaps([], spacing: 10, isDefaultSpacing: true), [])
    }

    // The Spacer cases are SwiftUI's measurements on macOS 27 (HStack(spacing: 0) in a frame).

    func testASpacerComesAfterTheOthersAndYieldsToAFlexibleSibling() {
        // One group would give the spacer and the flexible child 125 each; SwiftUI gives the
        // spacer its minimum and the flexible child the rest.
        XCTAssertEqual(sizes([.fixed(minimum: 50, natural: 50), .spacer(minimum: 8), .expanding(minimum: 0)], 300),
                       [50, 8, 242])
        XCTAssertEqual(sizes([.spacer(minimum: 50), .expanding(minimum: 0)], 300), [50, 250])
    }

    func testSpacersShareWhatTheOthersLeave() {
        XCTAssertEqual(sizes([.spacer(minimum: 8), .fixed(minimum: 50, natural: 50), .spacer(minimum: 8)], 200), [75, 50, 75])
        // The others overflow: the spacer keeps its minimum.
        XCTAssertEqual(sizes([.spacer(minimum: 8), .expanding(minimum: 350)], 300), [8, 350])
    }

    func testAmongUnboundedChildrenTheLargerMinimumGoesFirst() {
        // In source order the first would take 100 and the second its 150, overflowing to 250.
        XCTAssertEqual(sizes([.expanding(minimum: 0), .expanding(minimum: 150)], 200), [50, 150])
        XCTAssertEqual(sizes([.spacer(minimum: 8), .expanding(minimum: 100), .expanding(minimum: 0)], 300), [8, 146, 146])
    }

    func testDefaultSpacingIsZeroNextToASpacerOnly() {
        let children: [StackChild] = [.fixed(minimum: 20, natural: 20), .spacer(minimum: 8), .spacer(minimum: 8),
                                      .fixed(minimum: 20, natural: 20), .fixed(minimum: 20, natural: 20)]
        XCTAssertEqual(StackSolver.gaps(children, spacing: 8, isDefaultSpacing: true), [0, 0, 0, 8])
        XCTAssertEqual(StackSolver.gaps(children, spacing: 8, isDefaultSpacing: false), [8, 8, 8, 8], "explicit spacing applies everywhere")
        // SwiftUI: 20, two spacers of 80, 20 in 200 with default spacing.
        let row: [StackChild] = [.fixed(minimum: 20, natural: 20), .spacer(minimum: 8), .spacer(minimum: 8), .fixed(minimum: 20, natural: 20)]
        let gaps = StackSolver.gaps(row, spacing: 8, isDefaultSpacing: true)
        let result = StackSolver.mainSizes(row, available: 200, gaps: gaps)
        XCTAssertEqual(result, [20, 80, 80, 20])
        XCTAssertEqual(StackSolver.length(of: result, gaps: gaps), 200)
    }

    func testDocumentLengthsAreRoundedClampedAndNeverTrap() {
        XCTAssertEqual(StackSolver.length(7.5), 8)
        XCTAssertEqual(StackSolver.length(7.4), 7)
        XCTAssertEqual(StackSolver.length(7.2, rounding: .up), 8)
        XCTAssertEqual(StackSolver.length(-5), 0)
        XCTAssertEqual(StackSolver.length(.nan), 0)
        XCTAssertEqual(StackSolver.length(.infinity), 0)
        XCTAssertEqual(StackSolver.length(1e300), StackSolver.maximumLength, "Int(1e300) would trap")
        XCTAssertLessThan(StackSolver.maximumLength * 2, Int(Int32.max), "two of them still fit GTK's int")
    }

    func testPlacement() {
        XCTAssertEqual(StackSolver.centeredStart(length: 60, available: 100), 20)
        XCTAssertEqual(StackSolver.centeredStart(length: 120, available: 100), -10, "overflow is centered too")
        XCTAssertEqual(StackSolver.alignedOffset(size: 50, block: 80, alignment: .start), 0)
        XCTAssertEqual(StackSolver.alignedOffset(size: 50, block: 80, alignment: .center), 15)
        XCTAssertEqual(StackSolver.alignedOffset(size: 50, block: 80, alignment: .end), 30)
    }
}
