// Views/PropsValidation/HandConvertedPropsValidationTests.swift
/*
 Props against validation (see PropsValidationSupport.swift) for Slider, Toggle, TextField, VStack
 and List.
*/

import XCTest
@testable import ActionUI

@MainActor
final class SliderPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Slider", Slider.Props.init,
            casesByKey: [
                "value": [50, 50.5, "50", true],
                "range": [["min": 0, "max": 100], ["min": 5, "max": 1], ["min": 5], ["min": "a", "max": 1],
                          ["min": 2, "max": 2], "x", [String: Any]()],
                "step": [1, 0.5, 0, -1, "1"],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["range": ["min": 0, "max": 100], "step": 5],
                ["range": ["min": 0, "max": 10], "step": 200],
                ["range": ["min": 2, "max": 2], "step": 1],
                ["range": ["min": 5, "max": 1], "step": 0.25],
                ["range": "x", "step": 0.25],
                ["range": ["min": 0, "max": 100], "step": -3],
                ["range": ["min": 0, "max": 100], "step": "big"],
                // An invalid step on a range narrower than the 1.0 default, or on an empty range.
                ["range": ["min": 0, "max": 0.5], "step": -1],
                ["range": ["min": 0, "max": 0.5], "step": "big"],
                ["range": ["min": 2, "max": 2], "step": 0],
                ["value": 7, "range": ["min": 0.5, "max": 9.5], "step": 0.5, "valueChangeActionID": "changed"],
            ]
        )
    }
}

@MainActor
final class TogglePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Toggle", Toggle.Props.init,
            casesByKey: [
                "isOn": [true, false, "true", 1],
                "title": ["Enable", 5],
                // "checkbox" is valid on macOS, where these tests run.
                "style": ["switch", "button", "checkbox", "fancy", 5],
                "actionID": ["toggled", 5],
            ]
        )
    }
}

@MainActor
final class TextFieldPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "TextField", TextField.Props.init,
            casesByKey: [
                "title": ["Name", 5],
                "prompt": ["Enter", 5],
                "text": ["Hello", 5],
                "textContentType": ["username", 5],
                "format": ["integer", "decimal", "percent", "currency", "money", 5],
                "fractionLength": [2, ["min": 0, "max": 2], ["min": 1], [String: Any](), "2", 2.5],
                "currencyCode": ["EUR", 5],
                "axis": ["vertical", "horizontal", "diagonal", 5],
                "lineLimit": [3, ["min": 3], ["max": 5], ["min": 3, "max": 10], [String: Any](), ["min": "a"], "3"],
                // Float, Int64 and CGFloat: values a Swift caller can pass to setElementProperty.
                "value": [9.99, 9, "9.99", true, Float(2.5), Int64(3), CGFloat(1.5)],
                "actionID": ["submit", 5],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["format": "currency", "currencyCode": "EUR", "fractionLength": ["min": 0, "max": 2], "value": 9.99],
                ["format": "currency", "currencyCode": 5, "value": 1],
                ["format": "decimal", "fractionLength": 2.5, "value": "3.5"],
                ["format": "money", "value": 9.99, "text": "fallback"],
                ["format": "integer", "value": true, "text": "fallback"],
                ["format": "percent"],
                ["text": "Hello", "value": 5],
            ]
        )
    }
}

@MainActor
final class VStackPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "VStack", VStack.Props.init,
            casesByKey: [
                "spacing": [10, 10.5, "10", "inf", true],
                "alignment": ["leading", "center", "trailing", "top", 5],
            ]
        )
    }
}

@MainActor
final class ListPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "List", List.Props.init,
            casesByKey: [
                "itemType": [["viewType": "Button", "actionContext": "rowIndex", "actionID": "clicked"],
                             ["viewType": "Button", "actionContext": "bogus"], ["viewType": "Button"],
                             ["viewType": "Image", "dataInterpretation": "path"],
                             ["viewType": "Image", "dataInterpretation": "bogus"], ["viewType": "Image"],
                             ["viewType": "AsyncImage"], ["viewType": "Toggle"], ["viewType": "Fancy"],
                             ["viewType": "Text", "dataInterpretation": "bogus"], [String: Any](), "Text"],
                "actionID": ["selected", 5],
                "doubleClickActionID": ["opened", 5],
                "onRefreshActionID": ["refresh", 5],
                // grouped and insetGrouped do not exist on macOS, where these tests run: validation drops
                // them, Props keeps them and the renderer applies nothing (ListPropsTests covers them).
                "listStyle": ["automatic", "plain", "inset", "sidebar", "fancy", 5],
                "listRowBackground": ["blue", 5],
                "listRowSeparator": ["visible", "hidden", "automatic", "bogus", 5],
                "listRowSeparatorTint": ["gray", 5],
                "listRowInsets": [16, 16.5, ["top": 8], ["top": 8, "leading": 16, "bottom": 8, "trailing": 16],
                                  ["top": "x"], [String: Any](), "16", [1] as [Any]],
            ]
        )
    }
}
