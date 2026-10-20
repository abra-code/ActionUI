// Core/Elements/PhaseAnimatorPropsTests.swift
/*
 Tests for PhaseAnimator.Props: the phase values (an entry that is not a number counts as 0), the
 trigger, the timer interval, the state key and the animation. The "animation" key is also a base
 View key, read only as a valid curve with duration, delay, speed and value, so Props reads it
 through the base parser: nil without a valid curve, and never a "type".
*/

import XCTest
@testable import ActionUI

final class PhaseAnimatorPropsTests: XCTestCase {
    func testDefaults() {
        let props = PhaseAnimator.Props([:])
        XCTAssertEqual(props.values, [0.0, 1.0])
        XCTAssertEqual(props.trigger, "onAppear")
        XCTAssertEqual(props.timerInterval, 1.0)
        XCTAssertEqual(props.stateKey, "counter")
        XCTAssertNil(props.animation)
    }

    func testValidValues() {
        let props = PhaseAnimator.Props([
            "values": [0.0, 0.5, 2] as [Any], "trigger": "onStateChange", "timerInterval": 3, "stateKey": "clicks",
            "animation": ["curve": "easeIn", "duration": 0.5] as [String: Any],
        ])
        XCTAssertEqual(props.values, [0.0, 0.5, 2.0])
        XCTAssertEqual(props.trigger, "onStateChange")
        XCTAssertEqual(props.timerInterval, 3.0)
        XCTAssertEqual(props.stateKey, "clicks")
        XCTAssertEqual(props.animation?.curve, .easeIn)
        XCTAssertEqual(props.animation?.duration, 0.5)
    }

    func testValuesThatAreNotNumbersCountAsZero() {
        XCTAssertEqual(PhaseAnimator.Props(["values": [0.5, "x", "inf", true, false, NSNull(), [1] as [Any]] as [Any]]).values, [0.5, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
        XCTAssertEqual(PhaseAnimator.Props(["values": [Int32(2), UInt8(3), Float(1.5)] as [Any]]).values, [2.0, 3.0, 1.5])
        XCTAssertEqual(PhaseAnimator.Props(["values": [Any]()]).values, [])
        // Entries are read through NSNumber, as the renderer always did: a Decimal bridges to one.
        XCTAssertEqual(PhaseAnimator.Props(["values": [Decimal(string: "1.5")!, UInt64(7), CGFloat(0.25)] as [Any]]).values, [1.5, 7.0, 0.25])
    }

    func testValuesOfAnotherShapeFallBack() {
        for values: Any in ["x", 5, ["a": 1] as [String: Any]] {
            XCTAssertEqual(PhaseAnimator.Props(["values": values]).values, [0.0, 1.0], "\(values)")
        }
    }

    func testAnimationIsTheBaseParse() {
        XCTAssertEqual(PhaseAnimator.Props(["animation": "spring"]).animation?.curve, .spring)
        XCTAssertNil(PhaseAnimator.Props(["animation": "bogus"]).animation)
        XCTAssertNil(PhaseAnimator.Props(["animation": 5]).animation)
    }

    func testAnimationWithoutACurveIsNone() {
        // The dictionary form the renderer's own documentation shows has a "type", not a curve.
        XCTAssertNil(PhaseAnimator.Props(["animation": ["type": "spring", "duration": 0.5] as [String: Any]]).animation)
        XCTAssertNil(PhaseAnimator.Props(["animation": [String: Any]()]).animation)
    }

    func testAnimationDurationMustBePositive() {
        XCTAssertNil(PhaseAnimator.Props(["animation": ["curve": "linear", "duration": 0] as [String: Any]]).animation?.duration)
        XCTAssertNil(PhaseAnimator.Props(["animation": ["curve": "linear", "duration": "2"] as [String: Any]]).animation?.duration)
        XCTAssertEqual(PhaseAnimator.Props(["animation": ["curve": "linear", "duration": 2] as [String: Any]]).animation?.duration, 2.0)
    }

    func testWrongTypesFallBack() {
        let props = PhaseAnimator.Props(["trigger": 1, "timerInterval": "x", "stateKey": 2])
        XCTAssertEqual(props.trigger, "onAppear")
        XCTAssertEqual(props.timerInterval, 1.0)
        XCTAssertEqual(props.stateKey, "counter")
    }
}
