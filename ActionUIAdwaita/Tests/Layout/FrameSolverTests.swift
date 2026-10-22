// Tests/Layout/FrameSolverTests.swift
/*
 Tests for FrameSolver, SwiftUI's frame and padding arithmetic for one axis: what a fixed and a
 flexible frame report as their minimum and ideal size, when they expand and up to what, how
 SwiftUI normalizes the values, and how content sits in a box. No display needed.
*/

import XCTest
@testable import ActionUI

final class FrameSolverTests: XCTestCase {

    func testAFixedFrameIsItsSizeWhateverItsContentAndNeverExpands() {
        let frame = FrameAxis(fixed: 100)
        XCTAssertEqual(frame.minimumSize(content: 300), 100)
        XCTAssertEqual(frame.naturalSize(content: 300, contentMinimum: 300), 100)
        XCTAssertEqual(frame.expands, false)
        XCTAssertNil(frame.cap)
    }

    func testAnyMaximumExpandsUpToIt() {
        let infinite = FrameAxis.flexible(minimum: nil, ideal: nil, maximum: FrameAxis.infinity)
        XCTAssertEqual(infinite.expands, true)
        XCTAssertNil(infinite.cap)
        // A finite maximum expands too: the frame takes what it is offered, up to the maximum,
        // even when its content is smaller.
        let finite = FrameAxis.flexible(minimum: nil, ideal: nil, maximum: 300)
        XCTAssertEqual(finite.expands, true)
        XCTAssertEqual(finite.cap, 300)
    }

    func testOnlyAMinimumFollowsTheContent() {
        let frame = FrameAxis.flexible(minimum: 50, ideal: nil, maximum: nil)
        XCTAssertNil(frame.expands)
        XCTAssertEqual(frame.minimumSize(content: 10), 50)
        XCTAssertEqual(frame.naturalSize(content: 20, contentMinimum: 10), 50)
        XCTAssertEqual(frame.naturalSize(content: 80, contentMinimum: 10), 80)
        // A minimum below the content's: the frame can be that small, the content overflows it.
        XCTAssertEqual(frame.minimumSize(content: 70), 50)
    }

    func testOnlyAMaximumShrinksBelowItsContentsMinimumAtMost() {
        let frame = FrameAxis.flexible(minimum: nil, ideal: nil, maximum: 40)
        XCTAssertEqual(frame.minimumSize(content: 10), 10)
        XCTAssertEqual(frame.minimumSize(content: 90), 40)
        XCTAssertEqual(frame.naturalSize(content: 90, contentMinimum: 10), 40)
        XCTAssertEqual(frame.naturalSize(content: 30, contentMinimum: 10), 30)
    }

    func testTheIdealIsTheNaturalSize() {
        let frame = FrameAxis.flexible(minimum: 10, ideal: 200, maximum: FrameAxis.infinity)
        XCTAssertEqual(frame.naturalSize(content: 30, contentMinimum: 5), 200)
        XCTAssertEqual(frame.minimumSize(content: 5), 10)
    }

    func testValuesAreNormalizedAsSwiftUIDoes() {
        // Minimum at least 0, ideal at least the minimum, maximum at least the ideal.
        XCTAssertEqual(FrameAxis.flexible(minimum: -5, ideal: nil, maximum: nil).minimum, 0)
        XCTAssertEqual(FrameAxis.flexible(minimum: 50, ideal: 20, maximum: nil).ideal, 50)
        XCTAssertEqual(FrameAxis.flexible(minimum: 50, ideal: 80, maximum: 30).maximum, 80)
        // A minimum above the maximum: SwiftUI ignores both and sizes to the content.
        let invalid = FrameAxis.flexible(minimum: 50, ideal: nil, maximum: 30)
        XCTAssertNil(invalid.minimum)
        XCTAssertNil(invalid.maximum)
        XCTAssertNil(invalid.expands)
        XCTAssertEqual(invalid.naturalSize(content: 70, contentMinimum: 10), 70)
    }

    func testNegativePaddingIsKept() {
        XCTAssertEqual(StackSolver.signedLength(-5), -5)
        XCTAssertEqual(StackSolver.signedLength(-1e300), -StackSolver.maximumLength)
        XCTAssertEqual(StackSolver.signedLength(.nan), 0)
    }

    func testTheFrameInABoxBiggerThanItTakes() {
        // SwiftUI on macOS, each in a 300-wide parent: a fixed 100 frame of filling content stays
        // 100; frame(minWidth: 50) around a 10-wide content is 50; frame(maxWidth: 100) is 100;
        // no frame around a non-expanding content is the content.
        XCTAssertEqual(FrameAxis(fixed: 100).size(in: 300, contentMinimum: 0, contentNatural: 0, contentExpands: true), 100)
        let minimumOnly = FrameAxis.flexible(minimum: 50, ideal: nil, maximum: nil)
        XCTAssertEqual(minimumOnly.size(in: 300, contentMinimum: 10, contentNatural: 10, contentExpands: false), 50)
        XCTAssertEqual(minimumOnly.size(in: 300, contentMinimum: 10, contentNatural: 10, contentExpands: true), 300, "expanding content fills it")
        XCTAssertEqual(minimumOnly.size(in: 30, contentMinimum: 10, contentNatural: 10, contentExpands: false), 50, "never below its minimum")
        let maximumOnly = FrameAxis.flexible(minimum: nil, ideal: nil, maximum: 100)
        XCTAssertEqual(maximumOnly.size(in: 300, contentMinimum: 10, contentNatural: 10, contentExpands: false), 100)
        XCTAssertEqual(maximumOnly.size(in: 60, contentMinimum: 10, contentNatural: 10, contentExpands: false), 60)
        XCTAssertEqual(FrameAxis.none.size(in: 300, contentMinimum: 10, contentNatural: 40, contentExpands: false), 40)
        XCTAssertEqual(FrameAxis.none.size(in: 300, contentMinimum: 10, contentNatural: 40, contentExpands: true), 300)
    }

    func testPaddedContentInABox() {
        let padding = PaddingAxis(before: 10, after: 20)
        XCTAssertEqual(padding.total, 30)
        // Offered the box less the padding, clamped to its range.
        XCTAssertEqual(FrameSolver.contentSize(in: 100, padding: padding, minimum: 5, natural: 40, expands: false), 40)
        XCTAssertEqual(FrameSolver.contentSize(in: 100, padding: padding, minimum: 5, natural: 40, expands: true), 70)
        XCTAssertEqual(FrameSolver.contentSize(in: 50, padding: padding, minimum: 5, natural: 40, expands: false), 20)
        XCTAssertEqual(FrameSolver.contentSize(in: 20, padding: padding, minimum: 5, natural: 40, expands: false), 5,
                       "never below its minimum: it overflows")
    }
}
