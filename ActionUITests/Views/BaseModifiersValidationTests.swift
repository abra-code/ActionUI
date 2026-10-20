// Views/BaseModifiersValidationTests.swift
/*
 BaseModifiers built from raw properties must equal BaseModifiers built from the same properties
 after View.validateProperties, for valid and invalid values of every base key. That is what lets
 renderers read raw properties: BaseModifiers lets through exactly what validation let through.

 The cases are written the way JSON decoding produces values: Int for integral numbers,
 [String: Any] for objects, [Any] for arrays.
*/

import XCTest
@testable import ActionUI

@MainActor
final class BaseModifiersValidationTests: XCTestCase {
    private var logger: XCTestLogger!

    override func setUp() async throws {
        try await super.setUp()
        // Validation warns about every invalid case below; only errors would mean a problem.
        logger = XCTestLogger(maxLevel: .error)
    }

    override func tearDown() async throws {
        logger = nil
        try await super.tearDown()
    }

    /// One value per line for each base key: valid forms, edge cases, and invalid ones.
    private let casesByKey: [String: [Any]] = [
        "padding": [10, 10.5, "default", "DEFAULT", "inf", ["top": 5], ["top": "x", "leading": 5], ["top": "x"],
                    [String: Any](), "big", true, [1] as [Any]],
        "font": ["title", ["name": "Menlo", "size": 12], 12, true],
        "foregroundStyle": ["red", 5],
        "tint": ["blue", [1] as [Any]],
        "background": ["white", 3],
        "disabled": [true, false, "yes"],
        "hidden": [true, false, 1],
        "frame": [["width": 100], ["width": 100, "height": 50, "alignment": "topLeading"],
                  ["minWidth": 10, "maxWidth": "inf"], ["width": 10, "minWidth": 5], ["width": "wide"],
                  ["minHeight": 10, "maxHeight": true], ["alignment": "bottom"], ["alignment": "nowhere"],
                  ["alignment": 5], [String: Any](), ["foo": 1], ["width": 100, "alignment": "nowhere"], "100"],
        "backgroundAlignment": ["top", "nowhere", 5],
        "overlayAlignment": ["bottomTrailing", "nowhere", 5],
        "cornerRadius": [8, 8.5, "8"],
        "clipShape": ["circle", "capsule", "ellipse", "rectangle", "star",
                      ["type": "roundedRectangle", "cornerRadius": 12],
                      ["type": "roundedRectangle", "cornerRadiusX": 12, "cornerRadiusY": 8],
                      ["type": "roundedRectangle", "cornerRadiusX": 12], ["type": "star", "cornerRadius": 12], 5],
        "offset": [["x": 10], ["x": 10, "y": -5], ["x": "a"], [String: Any](), ["z": 1], 5],
        "opacity": [0.5, 0, 1, 1.5, -0.1, "0.5"],
        "textSelection": ["enabled", "disabled", "maybe", 1],
        "rotationEffect": [45, 45.5, "45"],
        "scaleEffect": [1.5, 2, ["x": 2], ["x": 2, "y": 0.5, "anchor": "top"], ["anchor": "top"], ["anchor": "nowhere"],
                        ["x": "a"], ["x": 2, "anchor": "nowhere"], ["x": 2, "anchor": 5], [String: Any](), "big"],
        "multilineTextAlignment": ["center", "leading", "trailing", "justified", 1],
        "zIndex": [1, 1.5, "1"],
        "border": [[String: Any](), ["color": "blue", "width": 2], ["color": 5], ["width": "thick"], ["foo": 1], "1"],
        "ignoresSafeArea": [true, false, ["edges": "top"], ["regions": "keyboard", "edges": "vertical"],
                            ["edges": "nowhere"], "all"],
        "buttonStyle": ["plain", "automatic", "borderless", "bordered", "borderedProminent", "fancy", 1],
        "controlSize": ["mini", "small", "regular", "large", "extraLarge", "huge", 1],
        "labelsHidden": [true, false, "true"],
        "scrollContentBackground": ["hidden", "visible", "automatic", "gone", 1],
        "shadow": [["radius": 5], ["color": "black", "radius": 5, "x": 1, "y": 2], [String: Any](), ["color": 5],
                   ["radius": "big"], ["foo": 1], 3],
        "animation": ["spring", "wobble",
                      ["curve": "easeIn", "duration": 0.3, "delay": 0.1, "speed": 2, "value": "opacity"],
                      ["curve": "linear", "duration": -1, "delay": -1, "speed": 0, "value": 5],
                      ["curve": "linear", "duration": 0, "delay": 0],
                      ["curve": "wobble"], ["duration": 1], 5],
        "transition": ["opacity", "slide", "scale", "move", "offset", "identity", "asymmetric", "spin",
                       ["type": "move", "edge": "top"], ["type": "move", "edge": "nowhere"],
                       ["type": "scale", "scale": 0.5, "anchor": "top"], ["type": "offset", "x": 5],
                       ["type": "asymmetric", "insertion": "opacity", "removal": ["type": "move", "edge": "bottom"]],
                       ["type": "asymmetric", "insertion": "spin"],
                       ["opacity", ["type": "scale"]] as [Any], ["spin"] as [Any], [Any](), [["opacity"] as [Any]] as [Any],
                       ["type": "spin"], 5],
        "openURLActionID": ["open", 5],
        "onAppearActionID": ["appear", 5],
        "onDisappearActionID": ["disappear", 5],
        "onHoverActionID": ["hover", 5],
        "navigationSplitViewColumnWidth": [400, 0, -5, ["ideal": 360], ["ideal": 360, "min": 280, "max": 480],
                                           ["ideal": 360, "min": -1, "max": 0], ["ideal": 0], ["min": 100], "400"],
        "keyboardShortcut": [["key": "a"], ["key": "a", "modifiers": [Any]()],
                             ["key": "a", "modifiers": ["Command", "shift", "shift"] as [Any]],
                             ["key": "a", "modifiers": ["hyper"] as [Any]], ["key": "a", "modifiers": "command"],
                             ["key": "a", "modifiers": ["command", 5] as [Any]],
                             ["key": "return"], ["key": "UpArrow"], ["key": "ab"], ["key": ""], ["key": 5],
                             [String: Any](), "a"],
        "navigationTitle": ["Detail", 5],
        "toolbarTitleDisplayMode": ["automatic", "inline", "large", "inlineLarge", "huge", 1],
        "help": ["Tip", 5],
        "accessibilityLabel": ["Label", 5],
        "accessibilityHint": ["Hint", 5],
        "accessibilityHidden": [true, "no"],
        "accessibilityIdentifier": ["id_1", 5],
        "sheetOnDismissActionID": ["sheet", 5],
        "fullScreenCoverOnDismissActionID": ["cover", 5],
        "searchable": [["actionID": "query"], ["actionID": "query", "prompt": "Search"], ["actionID": "query", "prompt": 5],
                       ["actionID": ""], ["prompt": "Search"], "query"],
        "popoverArrowEdge": ["bottom", "leading", "nowhere", 5],
        "popoverActionID": ["popover", 5],
        "actionID": ["row.selected", 5],
        "destinationViewId": [12, "12", 12.5, true],
    ]

    func testEveryKeyAloneMatchesValidation() {
        for (key, values) in casesByKey {
            for (index, value) in values.enumerated() {
                let raw: [String: Any] = [key: value]
                assertSameFields(
                    BaseModifiers(raw),
                    BaseModifiers(View.validateProperties(raw, logger)),
                    "for \(key) case \(index): \(value)"
                )
            }
        }
    }

    func testDropCombinationsMatchValidation() {
        let combinations: [[String: Any]] = [
            ["onDropActionID": "dropped", "onDropTypes": ["public.text"] as [Any]],
            ["onDropActionID": "dropped", "onDropTypes": ["public.text"] as [Any], "onDropTargetedActionID": "targeted"],
            ["onDropActionID": "dropped", "onDropTypes": ["public.text"] as [Any], "onDropTargetedActionID": 5],
            ["onDropActionID": "dropped", "onDropTypes": [Any]()],
            ["onDropActionID": "dropped", "onDropTypes": "public.text"],
            ["onDropActionID": 5, "onDropTypes": ["public.text"] as [Any]],
            ["onDropTypes": ["public.text"] as [Any]],
        ]
        for (index, raw) in combinations.enumerated() {
            assertSameFields(BaseModifiers(raw), BaseModifiers(View.validateProperties(raw, logger)), "drop case \(index)")
        }
    }

    func testAllValidKeysTogetherMatchValidation() {
        var raw: [String: Any] = [:]
        for (key, values) in casesByKey {
            raw[key] = values[0]
        }
        assertSameFields(BaseModifiers(raw), BaseModifiers(View.validateProperties(raw, logger)))
    }
}
