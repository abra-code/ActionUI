// Core/Elements/StepperPropsTests.swift
/*
 Tests for Stepper.Props: the value, the range guard (a reversed or partial range is no range), the step rule (not positive is 1) and the label keys.
*/

import XCTest
@testable import ActionUI

final class StepperPropsTests: XCTestCase {

    func testDefaults() {
        let props = Stepper.Props([:])
        XCTAssertEqual(props.initialValue, 0)
        XCTAssertNil(props.range)
        XCTAssertEqual(props.step, 1)
        XCTAssertEqual(props.label, "")
        XCTAssertNil(props.labelFormat)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = Stepper.Props([
            "value": 5, "range": ["min": 0, "max": 10], "step": 2.5, "label": "Qty", "labelFormat": "%.1f items", "actionID": "changed",
        ])
        XCTAssertEqual(props.initialValue, 5)
        XCTAssertEqual(props.range, 0...10)
        XCTAssertEqual(props.step, 2.5)
        XCTAssertEqual(props.label, "Qty")
        XCTAssertEqual(props.labelFormat, "%.1f items")
        XCTAssertEqual(props.actionID, "changed")
    }

    func testNonNumericValueIsZero() {
        XCTAssertEqual(Stepper.Props(["value": "5"]).initialValue, 0)
        XCTAssertEqual(Stepper.Props(["value": 2.5]).initialValue, 2.5)
    }

    func testUnusableRangeIsNoRange() {
        // A reversed range would trap in SwiftUI's min...max.
        for range: Any in [["min": 5, "max": 1], ["min": 5], ["max": 5], ["min": "a", "max": 1], "x", 3, [String: Any]()] {
            XCTAssertNil(Stepper.Props(["range": range]).range, "\(range)")
        }
    }

    func testAnEmptyRangeIsKept() {
        XCTAssertEqual(Stepper.Props(["range": ["min": 2, "max": 2]]).range, 2...2)
    }

    func testStepThatIsNotAPositiveNumberIsOne() {
        XCTAssertEqual(Stepper.Props(["step": 0]).step, 1)
        XCTAssertEqual(Stepper.Props(["step": -3]).step, 1)
        XCTAssertEqual(Stepper.Props(["step": "big"]).step, 1)
        XCTAssertEqual(Stepper.Props(["step": 0.25]).step, 0.25)
    }

    func testWrongTypesFallBack() {
        let props = Stepper.Props(["label": 5, "labelFormat": 5, "actionID": 5])
        XCTAssertEqual(props.label, "")
        XCTAssertNil(props.labelFormat)
        XCTAssertNil(props.actionID)
    }
}
