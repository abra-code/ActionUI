// Core/Elements/GaugePropsTests.swift
/*
 Tests for Gauge.Props: the value, the range (each bound defaults, bounds out of order are 0...1), the style names and which values the user may set.
*/

import XCTest
@testable import ActionUI

final class GaugePropsTests: XCTestCase {

    func testDefaults() {
        let props = Gauge.Props([:])
        XCTAssertEqual(props.initialValue, 0)
        XCTAssertEqual(props.min, 0)
        XCTAssertEqual(props.max, 1)
        XCTAssertNil(props.title)
        XCTAssertNil(props.style)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = Gauge.Props([
            "value": 50, "range": ["min": 0, "max": 100], "title": "Level", "style": "accessoryLinear", "valueChangeActionID": "changed",
        ])
        XCTAssertEqual(props.initialValue, 50)
        XCTAssertEqual(props.min, 0)
        XCTAssertEqual(props.max, 100)
        XCTAssertEqual(props.title, "Level")
        XCTAssertEqual(props.style, .accessoryLinear)
        XCTAssertEqual(props.valueChangeActionID, "changed")
    }

    func testIntegerRangeBounds() {
        // Integral bounds from JSON are read (they are not Doubles).
        let props = Gauge.Props(["range": ["min": 10, "max": 20]])
        XCTAssertEqual(props.min, 10)
        XCTAssertEqual(props.max, 20)
    }

    func testMissingOrNonNumericBoundDefaults() {
        let onlyMax = Gauge.Props(["range": ["max": 5]])
        XCTAssertEqual(onlyMax.min, 0)
        XCTAssertEqual(onlyMax.max, 5)
        let badMin = Gauge.Props(["range": ["min": "a", "max": 5]])
        XCTAssertEqual(badMin.min, 0)
        XCTAssertEqual(badMin.max, 5)
        let onlyMin = Gauge.Props(["range": ["min": 0.5]])
        XCTAssertEqual(onlyMin.min, 0.5)
        XCTAssertEqual(onlyMin.max, 1)
    }

    func testRangeOutOfOrderIsZeroToOne() {
        // A reversed range would trap in SwiftUI's min...max; {min: 5} alone is one (max defaults to 1).
        for range: Any in [["min": 5, "max": 1], ["min": 5], ["min": 2, "max": -2]] {
            let props = Gauge.Props(["range": range])
            XCTAssertEqual(props.min, 0, "\(range)")
            XCTAssertEqual(props.max, 1, "\(range)")
        }
    }

    func testRangeThatIsNotADictionaryIsZeroToOne() {
        for range: Any in ["x", 5, [1, 2] as [Any]] {
            let props = Gauge.Props(["range": range])
            XCTAssertEqual(props.min, 0, "\(range)")
            XCTAssertEqual(props.max, 1, "\(range)")
        }
    }

    func testAnEmptyRangeIsKept() {
        let props = Gauge.Props(["range": ["min": 3, "max": 3]])
        XCTAssertEqual(props.min, 3)
        XCTAssertEqual(props.max, 3)
    }

    func testNonNumericValueIsZero() {
        XCTAssertEqual(Gauge.Props(["value": "x"]).initialValue, 0)
    }

    func testStyleNames() {
        XCTAssertEqual(Gauge.Props(["style": "accessoryCircular"]).style, .accessoryCircular)
        XCTAssertEqual(Gauge.Props(["style": "accessoryCircularCapacity"]).style, .accessoryCircularCapacity)
        XCTAssertEqual(Gauge.Props(["style": "accessoryLinearCapacity"]).style, .accessoryLinearCapacity)
        // Unknown means no style modifier, as validation dropped it.
        XCTAssertNil(Gauge.Props(["style": "fancy"]).style)
        XCTAssertNil(Gauge.Props(["style": 5]).style)
    }

    func testAcceptsOnlyValuesInTheRange() {
        let props = Gauge.Props(["range": ["min": 1, "max": 3]])
        XCTAssertTrue(props.accepts(1))
        XCTAssertTrue(props.accepts(3))
        XCTAssertFalse(props.accepts(0.5))
        XCTAssertFalse(props.accepts(3.5))
    }

    func testTitleMustBeAString() {
        XCTAssertNil(Gauge.Props(["title": 5]).title)
    }
}
