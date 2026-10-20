// Core/Elements/SliderPropsTests.swift
/*
 Tests for Slider.Props: the value, the range guard (a reversed or partial range is 0...1), the
 step rules, and which values the user may set.
*/

import XCTest
@testable import ActionUI

final class SliderPropsTests: XCTestCase {

    func testDefaults() {
        let props = Slider.Props([:])
        XCTAssertEqual(props.initialValue, 0)
        XCTAssertEqual(props.min, 0)
        XCTAssertEqual(props.max, 1)
        XCTAssertNil(props.step)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = Slider.Props([
            "value": 50, "range": ["min": 0, "max": 100], "step": 5, "valueChangeActionID": "changed",
        ])
        XCTAssertEqual(props.initialValue, 50)
        XCTAssertEqual(props.min, 0)
        XCTAssertEqual(props.max, 100)
        XCTAssertEqual(props.step, 5)
        XCTAssertEqual(props.valueChangeActionID, "changed")
    }

    func testNonNumericValueIsZero() {
        XCTAssertEqual(Slider.Props(["value": "50"]).initialValue, 0)
        XCTAssertEqual(Slider.Props(["value": 2.5]).initialValue, 2.5)
    }

    func testUnusableRangeIsZeroToOne() {
        for range: Any in [["min": 5, "max": 1], ["min": 5], ["min": "a", "max": 1], "x", [String: Any]()] {
            let props = Slider.Props(["range": range])
            XCTAssertEqual(props.min, 0, "\(range)")
            XCTAssertEqual(props.max, 1, "\(range)")
        }
    }

    func testStepIsClampedToTheRange() {
        XCTAssertEqual(Slider.Props(["range": ["min": 0, "max": 10], "step": 200]).step, 10)
        XCTAssertEqual(Slider.Props(["range": ["min": 0, "max": 10], "step": 2.5]).step, 2.5)
        // An unusable range is 0...1, so the step is clamped to 1.
        XCTAssertEqual(Slider.Props(["range": "x", "step": 5]).step, 1)
    }

    func testStepWithAnEmptyRangeIsNone() {
        XCTAssertNil(Slider.Props(["range": ["min": 2, "max": 2], "step": 1]).step)
    }

    func testStepWithoutARangeIsOne() {
        XCTAssertEqual(Slider.Props(["step": 0.25]).step, 1)
    }

    func testStepThatIsNotAPositiveNumberIsOne() {
        XCTAssertEqual(Slider.Props(["range": ["min": 0, "max": 100], "step": 0]).step, 1)
        XCTAssertEqual(Slider.Props(["range": ["min": 0, "max": 100], "step": -3]).step, 1)
        XCTAssertEqual(Slider.Props(["range": ["min": 0, "max": 100], "step": "big"]).step, 1)
        // The default 1 is clamped to the range like a given step.
        XCTAssertEqual(Slider.Props(["range": ["min": 0, "max": 0.5], "step": -1]).step, 0.5)
        XCTAssertNil(Slider.Props(["range": ["min": 2, "max": 2], "step": 0]).step)
    }

    func testAcceptsOnlyValuesInTheRange() {
        let props = Slider.Props(["range": ["min": 1, "max": 3]])
        XCTAssertTrue(props.accepts(1))
        XCTAssertTrue(props.accepts(2.5))
        XCTAssertTrue(props.accepts(3))
        XCTAssertFalse(props.accepts(0.5))
        XCTAssertFalse(props.accepts(3.5))
    }
}
