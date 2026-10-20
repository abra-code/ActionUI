// Views/PropsValidation/ControlPropsValidationTests.swift
/*
 Props against validation (see PropsValidationSupport.swift) for Text, Label, LabeledContent, Link,
 Button, Image, AsyncImage, Stepper, ProgressView, Gauge, SecureField, TextEditor, Picker,
 ColorPicker, DatePicker, ContentUnavailableView, ControlGroup, Menu and DisclosureGroup.
 ColorPicker's and DatePicker's values (a Color, a Date) are not properties, so Props covers only
 their other keys.
*/

import XCTest
@testable import ActionUI

@MainActor
final class TextPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Text", Text.Props.init,
            casesByKey: [
                "text": ["Hello", "", 5, true],
                "markdown": ["**Bold**", "", 5, true],
            ],
            combinations: [
                ["text": "plain", "markdown": "**rich**"],
                ["text": "plain", "markdown": 5],
            ]
        )
    }
}

@MainActor
final class LabelPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Label", Label.Props.init,
            casesByKey: [
                "title": ["Title", "", 5],
                "systemImage": ["star.fill", "", 5],
                "imageName": ["custom", "", 5],
            ],
            combinations: [
                ["title": "T", "systemImage": "star", "imageName": "custom"],
                ["title": 1, "systemImage": 2, "imageName": 3],
            ]
        )
    }
}

@MainActor
final class LabeledContentPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "LabeledContent", LabeledContent.Props.init,
            casesByKey: [
                "title": ["Username", "", 5, true],
            ]
        )
    }
}

@MainActor
final class LinkPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Link", Link.Props.init,
            casesByKey: [
                "title": ["Visit", "", 5],
                "url": ["https://example.com", "not a url", "", 5],
            ],
            combinations: [
                ["title": "Visit", "url": "https://example.com"],
                ["title": 1, "url": 2],
            ]
        )
    }
}

@MainActor
final class ButtonPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Button", Button.Props.init,
            casesByKey: [
                "title": ["Click", "", 5],
                "systemImage": ["plus", "", 5],
                "assetImage": ["Logo", "", 5],
                "imageScale": ["small", "medium", "large", "Large", "SMALL", "huge", 5],
                "role": ["destructive", "cancel", "primary", "Destructive", 5],
                "actionID": ["clicked", 5],
                "popoverActionID": ["popped", 5],
            ],
            combinations: [
                ["title": "Delete", "systemImage": "trash", "imageScale": "large", "role": "destructive", "actionID": "delete"],
                ["title": 1, "systemImage": 2, "assetImage": 3, "imageScale": 4, "role": 5, "actionID": 6],
            ]
        )
    }
}

/// What Image.Props leaves to the renderer is the choice among several sources: validation keeps
/// only the first of them, Props lists them all. The first is compared.
private struct ImageChoice {
    var source: Image.Props.Source?
    var contentMode: Image.Props.ContentMode?
    var resizable: Bool
    var imageScale: Image.Props.ImageScale?

    init(_ properties: [String: Any]) {
        let props = Image.Props(properties)
        source = props.sources.first
        contentMode = props.contentMode
        resizable = props.resizable
        imageScale = props.imageScale
    }
}

@MainActor
final class ImagePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        // File paths here are images, PDFs or have no known extension. One with a known non-image
        // extension is dropped by validation and skipped by the renderer (the type table is the
        // platform's), so Props keeps it as a source; the explicit tests cover that.
        assertPropsMatchValidation(
            elementType: "Image", ImageChoice.init,
            casesByKey: [
                "systemName": ["star", "", 5],
                "assetName": ["custom", "", 5],
                "resourceName": ["a.png", "", 5],
                "filePath": ["/tmp/a.png", "/tmp/a.jpg", "/tmp/a.pdf", "/tmp/noextension", "", 5],
                "resizable": [true, false, "true", 1],
                "contentMode": ["fit", "fill", "stretch", "Fit", 5],
                "scaleMode": ["fit", "fill", "stretch", 5],
                "imageScale": ["small", "medium", "large", "Large", "huge", 5],
            ],
            combinations: [
                ["systemName": "s", "assetName": "a"],
                ["systemName": "s", "assetName": "a", "resourceName": "r"],
                ["systemName": "s", "assetName": "a", "resourceName": "r", "filePath": "/tmp/f.png"],
                ["systemName": "s", "filePath": "/tmp/f.png"],
                ["assetName": "a", "resourceName": "r"],
                ["systemName": 5, "assetName": "a"],
                ["filePath": 5, "resourceName": "r", "assetName": "a"],
                ["contentMode": "fit", "scaleMode": "fill"],
                ["contentMode": "stretch", "scaleMode": "fill"],
                ["contentMode": 5, "scaleMode": "fit"],
                ["contentMode": "fit", "scaleMode": "stretch"],
                ["scaleMode": "fill", "resizable": false],
                ["contentMode": "fill", "resizable": false],
                ["contentMode": "stretch", "resizable": true],
                ["systemName": "star", "contentMode": "fit", "imageScale": "large", "resizable": true],
            ]
        )
    }
}

@MainActor
final class AsyncImagePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "AsyncImage", AsyncImage.Props.init,
            casesByKey: [
                "url": ["https://example.com/a.jpg", "invalid-url", "", 5],
                "placeholder": ["star", "", 5],
                "resizable": [true, false, "false", 1],
                "contentMode": ["fit", "fill", "stretch", "Fill", 5],
            ],
            combinations: [
                ["url": "https://example.com/a.jpg", "placeholder": "star", "resizable": false, "contentMode": "fill"],
                ["url": 1, "placeholder": 2, "resizable": 3, "contentMode": 4],
            ]
        )
    }
}

@MainActor
final class StepperPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Stepper", Stepper.Props.init,
            casesByKey: [
                "value": [5, 5.5, 0, -2, "5", "inf", true],
                "range": [["min": 0, "max": 10], ["min": 0.5, "max": 9.5], ["min": 5, "max": 1], ["min": 5],
                          ["max": 5], ["min": "a", "max": 1], ["min": 2, "max": 2], ["min": "inf", "max": "inf"],
                          "x", 5, [String: Any]()],
                "step": [1, 0.5, 2, 0, -1, "1", "inf", true],
                "label": ["Qty", "", 5],
                "labelFormat": ["%.0f items", "", 5],
                "actionID": ["changed", 5],
            ],
            combinations: [
                ["value": 3, "range": ["min": 0, "max": 10], "step": 2, "label": "Qty", "actionID": "changed"],
                ["range": ["min": 5, "max": 1], "step": 0],
                ["range": ["min": 0, "max": 10], "step": -1, "labelFormat": "%.1f"],
                ["value": "x", "range": "x", "step": "x", "label": 1, "labelFormat": 2, "actionID": 3],
            ]
        )
    }
}

@MainActor
final class ProgressViewPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ProgressView", ProgressView.Props.init,
            casesByKey: [
                "value": [0, 3, 0.5, -1, -0.5, "x", "inf", true],
                "total": [1, 10, 0.5, 0, -2, "x", "inf", true],
                "title": ["Loading", "", 5],
                "progressViewStyle": ["automatic", "linear", "circular", "bar", "Linear", 5],
                "actionID": ["tapped", 5],
            ],
            combinations: [
                ["value": 3, "total": 10, "title": "Loading", "progressViewStyle": "linear", "actionID": "tapped"],
                ["value": -1, "total": 0],
                ["value": 0, "total": 0],
                ["value": 20, "total": 10],
                ["value": "x", "total": "x", "title": 1, "progressViewStyle": 2, "actionID": 3],
            ]
        )
    }
}

@MainActor
final class GaugePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Gauge", Gauge.Props.init,
            casesByKey: [
                "value": [50, 0.5, 0, -3, "x", "inf", true],
                "range": [["min": 0, "max": 100], ["min": 0.5, "max": 9.5], ["min": 5, "max": 1], ["min": 5],
                          ["max": 5], ["max": -5], ["min": "a", "max": 1], ["min": 1, "max": "b"],
                          ["min": "a", "max": "b"], ["min": 2, "max": 2], ["min": "inf", "max": "inf"],
                          "x", 5, [1, 2] as [Any], [String: Any]()],
                "title": ["Level", "", 5],
                "style": ["accessoryCircular", "accessoryCircularCapacity", "accessoryLinear",
                          "accessoryLinearCapacity", "fancy", "Linear", 5],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["value": 5, "range": ["min": 0, "max": 10], "title": "Level", "style": "accessoryLinear", "valueChangeActionID": "changed"],
                ["value": "x", "range": "x", "title": 1, "style": 2, "valueChangeActionID": 3],
                ["range": ["min": 5, "max": 1], "style": "fancy"],
            ]
        )
    }
}

@MainActor
final class SecureFieldPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "SecureField", SecureField.Props.init,
            casesByKey: [
                "title": ["Password", "", 5],
                "prompt": ["Enter", "", 5],
                "text": ["secret", "", 5],
                "textContentType": ["password", "newPassword", "oneTimeCode", "username", "", 5],
                "actionID": ["submit", 5],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["title": "P", "prompt": "p", "text": "t", "textContentType": "password", "actionID": "a", "valueChangeActionID": "v"],
                ["title": 1, "prompt": 2, "text": 3, "textContentType": 4, "actionID": 5, "valueChangeActionID": 6],
            ]
        )
    }
}

@MainActor
final class TextEditorPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "TextEditor", TextEditor.Props.init,
            casesByKey: [
                "text": ["Hello", "", 5],
                "markdown": ["**Hi**", "", 5],
                "placeholder": ["Type", "", 5],
                "readOnly": [true, false, "true", 1],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["text": "t", "markdown": "**m**", "placeholder": "p", "readOnly": true, "valueChangeActionID": "v"],
                ["text": 1, "markdown": 2, "placeholder": 3, "readOnly": 4, "valueChangeActionID": 5],
                ["text": 1, "markdown": "**m**"],
            ]
        )
    }
}

@MainActor
final class PickerPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Picker", Picker.Props.init,
            casesByKey: [
                "title": ["Size", "", 5],
                "options": [
                    ["S", "M", "L"] as [Any],
                    [Any](),
                    [["title": "Red", "tag": "r"], ["title": "Blue", "tag": "b"]] as [Any],
                    [["title": "Red", "tag": "r"], ["title": "", "tag": "x"], ["title": "NoTag"], ["tag": "notitle"],
                     ["title": 5, "tag": "t"], ["title": "Blue", "tag": ""]] as [Any],
                    [["title": "A", "tag": "a"], ["section": "More"], ["title": "B", "tag": "b"],
                     ["divider": true], ["title": "C", "tag": "c"]] as [Any],
                    [["section": "First"], ["title": "A", "tag": "a"]] as [Any],
                    [["divider": true], ["title": "A", "tag": "a"]] as [Any],
                    [["title": "A", "tag": "a"], ["divider": true]] as [Any],
                    [["divider": false], ["section": 5], ["title": "A", "tag": "a"]] as [Any],
                    [[String: Any]()] as [Any],
                    [1, 2] as [Any],
                    [["title": "A", "tag": "a"], "B"] as [Any],
                    "x", 5,
                ],
                // "wheel" is dropped by validation on macOS, where these tests run, and kept
                // elsewhere; the explicit tests cover it.
                "pickerStyle": ["menu", "segmented", "radioGroup", "fancy", 5],
                "horizontalRadioGroupLayout": [true, false, "true", 1],
                "actionID": ["picked", 5],
            ],
            combinations: [
                ["title": "Size", "options": ["S", "M"] as [Any], "pickerStyle": "radioGroup",
                 "horizontalRadioGroupLayout": true, "actionID": "picked"],
                ["title": 1, "options": 2, "pickerStyle": 3, "horizontalRadioGroupLayout": 4, "actionID": 5],
            ]
        )
    }
}

@MainActor
final class ColorPickerPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ColorPicker", ColorPicker.Props.init,
            casesByKey: [
                "title": ["Tint", "", 5],
                "selectedColor": ["#FF0000", "red", "", 5],
                "actionID": ["picked", 5],
            ],
            combinations: [
                ["title": "Tint", "selectedColor": "blue", "actionID": "picked"],
                ["title": 1, "selectedColor": 2, "actionID": 3],
            ]
        )
    }
}

@MainActor
final class DatePickerPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "DatePicker", DatePicker.Props.init,
            casesByKey: [
                "title": ["When", "", 5],
                // "stepperField" and "field" are valid on macOS, where these tests run.
                "displayStyle": ["automatic", "compact", "graphical", "stepperField", "field", "wheel", 5],
                "displayedComponents": ["date", "hourAndMinute", "dateAndTime", "time", 5],
                "range": [
                    ["start": "2023-01-01", "end": "2025-12-31"] as [String: Any],
                    ["start": "2023-01-01"] as [String: Any],
                    ["end": "2025-12-31"] as [String: Any],
                    [String: Any](),
                    ["start": 1, "end": 2] as [String: Any],
                    ["start": "2023-01-01", "end": 2] as [String: Any],
                    ["start": "later", "end": "earlier"] as [String: Any],
                    ["start": "2023-01-01", "end": "2025-12-31", "extra": "x"] as [String: Any],
                    "x", 5,
                ],
                "selectedDate": ["2024-07-16", "12:30", "", 5],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["title": "When", "displayStyle": "graphical", "displayedComponents": "dateAndTime",
                 "range": ["start": "2023-01-01", "end": "2025-12-31"], "selectedDate": "2024-07-16",
                 "valueChangeActionID": "changed"],
                ["title": 1, "displayStyle": 2, "displayedComponents": 3, "range": 4, "selectedDate": 5,
                 "valueChangeActionID": 6],
            ]
        )
    }
}

@MainActor
final class ContentUnavailableViewPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ContentUnavailableView", ContentUnavailableView.Props.init,
            casesByKey: [
                "title": ["Empty", "", 5],
                "systemImage": ["tray", "", 5],
                "description": ["Nothing here", "", 5],
                "search": [true, false, "true", 1],
                "query": ["cats", "", 5],
            ],
            combinations: [
                ["title": "Empty", "systemImage": "tray", "description": "d"],
                ["search": true, "query": "cats", "title": "ignored"],
                ["search": "yes", "query": 5, "title": 6, "systemImage": 7, "description": 8],
            ]
        )
    }
}

@MainActor
final class ControlGroupPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ControlGroup", ControlGroup.Props.init,
            casesByKey: [
                "title": ["Actions", "", 5, true],
            ]
        )
    }
}

@MainActor
final class MenuPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "Menu", Menu.Props.init,
            casesByKey: [
                "title": ["File", "", 5, true],
            ]
        )
    }
}

@MainActor
final class DisclosureGroupPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "DisclosureGroup", DisclosureGroup.Props.init,
            casesByKey: [
                "title": ["Details", "", 5],
                "isExpanded": [true, false, "true", 1],
                "valueChangeActionID": ["toggled", 5],
            ],
            combinations: [
                ["title": "Details", "isExpanded": true, "valueChangeActionID": "toggled"],
                ["title": 1, "isExpanded": 2, "valueChangeActionID": 3],
            ]
        )
    }
}
