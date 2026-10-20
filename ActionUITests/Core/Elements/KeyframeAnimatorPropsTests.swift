// Core/Elements/KeyframeAnimatorPropsTests.swift
/*
 Tests for KeyframeAnimator.Props: the initial values, the trigger and its timer interval and state
 key, the repeat count (only an Int counts), the autoreverse flag, the delay and the keyframes (raw
 dictionaries, all or nothing). A timer interval of 0 or less is not guarded: it reaches the timer.
*/

import XCTest
@testable import ActionUI

final class KeyframeAnimatorPropsTests: XCTestCase {
    func testDefaults() {
        let props = KeyframeAnimator.Props([:])
        XCTAssertEqual(props.initialValue, AnimationValues())
        XCTAssertEqual(props.trigger, "onAppear")
        XCTAssertEqual(props.timerInterval, 1.0)
        XCTAssertEqual(props.stateKey, "counter")
        XCTAssertEqual(props.repeatCount, 1)
        XCTAssertFalse(props.autoreverses)
        XCTAssertEqual(props.delay, 0.0)
        XCTAssertEqual(props.keyframes.count, 0)
    }

    func testValidValues() {
        let props = KeyframeAnimator.Props([
            "initialValue": ["opacity": 0.5, "scale": 2, "rotation": 45] as [String: Any],
            "trigger": "onTimer", "timerInterval": 2, "stateKey": "clicks",
            "repeat": ["count": 3, "autoreverses": true] as [String: Any],
            "delay": 1.5,
            "keyframes": ["0%": ["type": "linear", "duration": 0.8] as [String: Any], "100%": ["type": "spring"] as [String: Any]] as [String: Any],
        ])
        XCTAssertEqual(props.initialValue, AnimationValues(opacity: 0.5, scale: 2.0, rotation: 45.0))
        XCTAssertEqual(props.trigger, "onTimer")
        XCTAssertEqual(props.timerInterval, 2.0)
        XCTAssertEqual(props.stateKey, "clicks")
        XCTAssertEqual(props.repeatCount, 3)
        XCTAssertTrue(props.autoreverses)
        XCTAssertEqual(props.delay, 1.5)
        XCTAssertEqual(props.keyframes.keys.sorted(), ["0%", "100%"])
        XCTAssertEqual(props.keyframes["0%"]?["duration"] as? Double, 0.8)
    }

    func testInitialValueFillsMissingOrNonNumericEntriesWithTheirDefaults() {
        XCTAssertEqual(KeyframeAnimator.Props(["initialValue": ["scale": 3] as [String: Any]]).initialValue, AnimationValues(opacity: 1.0, scale: 3.0, rotation: 0.0))
        XCTAssertEqual(KeyframeAnimator.Props(["initialValue": ["opacity": "half"] as [String: Any]]).initialValue, AnimationValues())
        XCTAssertEqual(KeyframeAnimator.Props(["initialValue": "x"]).initialValue, AnimationValues())
    }

    func testRepeatCountMustBeAnInt() {
        XCTAssertEqual(KeyframeAnimator.Props(["repeat": ["count": 3.5] as [String: Any]]).repeatCount, 1)
        XCTAssertEqual(KeyframeAnimator.Props(["repeat": ["count": "3"] as [String: Any]]).repeatCount, 1)
        XCTAssertEqual(KeyframeAnimator.Props(["repeat": 3]).repeatCount, 1)
        XCTAssertFalse(KeyframeAnimator.Props(["repeat": ["autoreverses": "yes"] as [String: Any]]).autoreverses)
    }

    func testNumbersAcceptAnyJSONNumber() {
        XCTAssertEqual(KeyframeAnimator.Props(["timerInterval": 3]).timerInterval, 3.0)
        XCTAssertEqual(KeyframeAnimator.Props(["delay": 2]).delay, 2.0)
        XCTAssertEqual(KeyframeAnimator.Props(["timerInterval": "2"]).timerInterval, 1.0)
        XCTAssertEqual(KeyframeAnimator.Props(["delay": "1"]).delay, 0.0)
    }

    func testTimerIntervalIsNotGuarded() {
        XCTAssertEqual(KeyframeAnimator.Props(["timerInterval": 0]).timerInterval, 0.0)
        XCTAssertEqual(KeyframeAnimator.Props(["timerInterval": -1]).timerInterval, -1.0)
    }

    func testKeyframesAreAllOrNothing() {
        XCTAssertEqual(KeyframeAnimator.Props(["keyframes": ["0%": 5] as [String: Any]]).keyframes.count, 0)
        XCTAssertEqual(KeyframeAnimator.Props(["keyframes": ["0%": ["type": "cubic"] as [String: Any], "100%": "x"] as [String: Any]]).keyframes.count, 0)
        XCTAssertEqual(KeyframeAnimator.Props(["keyframes": [Any]()]).keyframes.count, 0)
    }

    func testWrongTypesFallBack() {
        let props = KeyframeAnimator.Props(["trigger": 1, "stateKey": 2])
        XCTAssertEqual(props.trigger, "onAppear")
        XCTAssertEqual(props.stateKey, "counter")
    }
}
