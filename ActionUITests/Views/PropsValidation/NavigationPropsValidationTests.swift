// Views/PropsValidation/NavigationPropsValidationTests.swift
/*
 Props against validation (see PropsValidationSupport.swift) for NavigationLink, NavigationSplitView,
 TabView, Table, ScrollView, ScrollViewReader, GeometryReader, LoadableView, ToolbarItem and
 ToolbarItemGroup. NavigationStack, Tab, and the subviews of the others have no properties of their
 own to parse.
*/

import XCTest
@testable import ActionUI

@MainActor
final class NavigationLinkPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "NavigationLink", NavigationLink.Props.init,
            casesByKey: [
                "title": ["Go", "", 5, true],
                "destinationViewId": [10, 0, -1, 10.0, 10.5, "10", true],
            ],
            combinations: [
                ["title": "Go", "destinationViewId": 10],
                ["title": 1, "destinationViewId": "x"],
            ]
        )
    }
}

@MainActor
final class NavigationSplitViewPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "NavigationSplitView", NavigationSplitView.Props.init,
            casesByKey: [
                "columnVisibility": ["automatic", "all", "doubleColumn", "detail", "sideways", "All", "", 5],
                "style": ["automatic", "balanced", "prominentDetail", "wide", "Balanced", "", 5],
                "valueChangeActionID": ["changed", 5],
            ],
            combinations: [
                ["columnVisibility": "detail", "style": "balanced", "valueChangeActionID": "changed"],
                ["columnVisibility": 1, "style": 2, "valueChangeActionID": 3],
                ["columnVisibility": "bogus", "style": "bogus"],
            ]
        )
    }
}

@MainActor
final class TabViewPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "TabView", TabView.Props.init,
            casesByKey: [
                "selection": [0, 2, -1, 1.0, 1.5, "1", true],
                "style": ["automatic", "tabBarOnly", "sidebarAdaptable", "page", "verticalPage", "grouped",
                          "fancy", "Page", "", 5],
                "actionID": ["tab.changed", 5],
            ],
            combinations: [
                ["selection": 1, "style": "page", "actionID": "tab.changed"],
                ["selection": "x", "style": 5, "actionID": 6],
                ["selection": 1.5, "style": "bogus"],
            ]
        )
    }
}

@MainActor
final class TablePropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        let threeColumns: [Any] = ["A", "B", "C"]
        assertPropsMatchValidation(
            elementType: "Table", Table.Props.init,
            casesByKey: [
                "columns": [threeColumns, [Any](), ["A", 5] as [Any], "A", 5],
                "columnTypes": [
                    [["viewType": "Button", "actionContext": "rowIndex", "actionID": "go"]] as [Any],
                    [["viewType": "Fancy"]] as [Any],
                    [["viewType": 5]] as [Any],
                    [[String: Any]()] as [Any],
                    [["viewType": "Text"], 5] as [Any],
                    "Text", 5, [Any](),
                ],
                "widths": [[100, 80, 40] as [Any], [Any](), [100.5, 80] as [Any], [100, "80"] as [Any], "100", 5],
                "minWidths": [[80, 60, 30] as [Any], [Any](), [80.5] as [Any], [80, "60"] as [Any], "80", 5],
                "columnHeadersVisibility": ["automatic", "hidden", "visible", "gone", "Hidden", "", 5],
                "actionID": ["selected", 5],
                "doubleClickActionID": ["double", 5],
            ],
            combinations: [
                // viewType: every name, an unknown one, a wrong type, and missing entries padded.
                ["columns": threeColumns, "columnTypes": [["viewType": "Text"], ["viewType": "Button"], ["viewType": "Toggle"]] as [Any]],
                ["columns": threeColumns, "columnTypes": [["viewType": "Image"], ["viewType": "AsyncImage"]] as [Any]],
                ["columns": threeColumns, "columnTypes": [["viewType": "Nope"], ["viewType": 5], [String: Any]()] as [Any]],
                ["columns": ["A"] as [Any], "columnTypes": [["viewType": "Button"], ["viewType": "Toggle"], ["viewType": "Image"]] as [Any]],
                ["columns": threeColumns, "columnTypes": [Any]()],
                ["columns": 5, "columnTypes": [["viewType": "Image"]] as [Any]],
                ["columnTypes": [["viewType": "Image"]] as [Any]],
                // A list with an entry that is not a dictionary is no list.
                ["columns": threeColumns, "columnTypes": [["viewType": "Button"], "Toggle"] as [Any]],
                // Image: dataInterpretation names, missing, unknown, wrong type.
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Image", "dataInterpretation": "path"],
                    ["viewType": "Image", "dataInterpretation": "assetName"],
                    ["viewType": "Image"],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Image", "dataInterpretation": "mixed"],
                    ["viewType": "Image", "dataInterpretation": "bogus"],
                    ["viewType": "Image", "dataInterpretation": 5],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Image", "dataInterpretation": "systemName"],
                    ["viewType": "Image", "dataInterpretation": "resourceName"],
                ] as [Any]],
                // Button: actionContext names, missing, unknown; dataInterpretation names, unknown, wrong type.
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Button", "actionContext": "title"],
                    ["viewType": "Button", "actionContext": "rowIndex"],
                    ["viewType": "Button", "actionContext": "columnIndex"],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Button", "actionContext": "rowColumnIndex", "actionID": "go"],
                    ["viewType": "Button", "actionContext": "bogus"],
                    ["viewType": "Button", "actionContext": 5, "actionID": 6],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Button", "dataInterpretation": "path"],
                    ["viewType": "Button", "dataInterpretation": "bogus"],
                    ["viewType": "Button", "dataInterpretation": 5],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Button", "dataInterpretation": "systemName"],
                    ["viewType": "Button", "dataInterpretation": "mixed"],
                    ["viewType": "Button"],
                ] as [Any]],
                // Toggle: style names, unknown, wrong type; disabledColumn values.
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Toggle", "style": "checkbox"],
                    ["viewType": "Toggle", "style": "switch"],
                    ["viewType": "Toggle", "style": "button"],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Toggle", "style": "bogus"],
                    ["viewType": "Toggle", "style": 5],
                    ["viewType": "Toggle"],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Toggle", "disabledColumn": 1],
                    ["viewType": "Toggle", "disabledColumn": 3, "actionID": "toggled"],
                    ["viewType": "Toggle", "disabledColumn": 99],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Toggle", "disabledColumn": 0],
                    ["viewType": "Toggle", "disabledColumn": -2],
                    ["viewType": "Toggle", "disabledColumn": "2"],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Toggle", "disabledColumn": 2.0],
                    ["viewType": "Toggle", "disabledColumn": 1.5],
                    ["viewType": "Toggle", "disabledColumn": true],
                ] as [Any]],
                // Keys of one type on a cell of another type are not read.
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Text", "style": "switch", "disabledColumn": 0, "actionContext": "bogus", "dataInterpretation": "bogus"],
                    ["viewType": "AsyncImage", "style": 5, "disabledColumn": 2, "actionContext": "rowIndex", "dataInterpretation": "path"],
                    ["viewType": "Fancy", "style": "bogus", "disabledColumn": -1, "actionContext": 5, "dataInterpretation": 5],
                ] as [Any]],
                ["columns": threeColumns, "columnTypes": [
                    ["viewType": "Button", "style": "bogus", "disabledColumn": 0],
                    ["viewType": "Image", "actionContext": "bogus", "style": "switch"],
                    ["viewType": "Toggle", "actionContext": "bogus", "dataInterpretation": "bogus"],
                ] as [Any]],
                // The rest together.
                ["columns": threeColumns, "widths": [100, 80, 40] as [Any], "minWidths": [80, 60, 30] as [Any],
                 "columnHeadersVisibility": "hidden", "actionID": "selected", "doubleClickActionID": "double"],
                ["columns": 1, "columnTypes": 2, "widths": 3, "minWidths": 4, "columnHeadersVisibility": 5,
                 "actionID": 6, "doubleClickActionID": 7],
            ]
        )
    }
}

@MainActor
final class ScrollViewPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ScrollView", ScrollView.Props.init,
            casesByKey: [
                "axis": ["vertical", "horizontal", "both", "diagonal", "Vertical", "", 5],
                "showsIndicators": [true, false, "false", 0, 1, 5.0],
                "onRefreshActionID": ["refresh", "", 5],
            ],
            combinations: [
                ["axis": "both", "showsIndicators": false, "onRefreshActionID": "refresh"],
                ["axis": 1, "showsIndicators": "no", "onRefreshActionID": 3],
                ["axis": "bogus", "showsIndicators": "bogus"],
            ]
        )
    }
}

@MainActor
final class ScrollViewReaderPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ScrollViewReader", ScrollViewReader.Props.init,
            casesByKey: [
                "scrollTo": [5, 0, -1, 5.0, 5.5, "5", true],
                "anchor": ["top", "center", "bottom", "leading", "Top", "", 5],
            ],
            combinations: [
                ["scrollTo": 5, "anchor": "bottom"],
                ["scrollTo": "x", "anchor": 3],
                ["scrollTo": 5, "anchor": "bogus"],
            ]
        )
    }
}

@MainActor
final class GeometryReaderPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "GeometryReader", GeometryReader.Props.init,
            casesByKey: [
                "alignment": ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading",
                              "bottom", "bottomTrailing", "middle", "Center", "", 5],
            ]
        )
    }
}

@MainActor
final class LoadableViewPropsValidationTests: PropsValidationTestCase {
    // Validation logs an error (which the test logger fails on) when no source is left, so every
    // case here keeps at least one valid source. A property set with none at all, and a
    // viewDidLoadActionID that is not a string, are covered in LoadableViewPropsTests.
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "LoadableView", LoadableView.Props.init,
            casesByKey: [
                "url": ["https://example.com/view.json", ""],
                "filePath": ["/tmp/view.json", ""],
                "name": ["Hello.json", ""],
            ],
            combinations: [
                // Two or three sources: url wins over filePath, filePath over name.
                ["url": "https://a", "filePath": "/b", "name": "c"],
                ["url": "https://a", "filePath": "/b"],
                ["url": "https://a", "name": "c"],
                ["filePath": "/b", "name": "c"],
                // A source of the wrong type does not count, so a lower one can win.
                ["url": 5, "filePath": "/b", "name": "c"],
                ["url": "https://a", "filePath": 5, "name": "c"],
                ["url": 5, "filePath": 6, "name": "c"],
                ["url": 5, "name": "c"],
                ["filePath": 5, "name": "c"],
                ["url": "", "filePath": "/b"],
                ["url": "https://a", "viewDidLoadActionID": "loaded"],
                ["name": "c", "viewDidLoadActionID": "loaded"],
                ["name": "c", "viewDidLoadActionID": 5],
            ]
        )
    }
}

@MainActor
final class ToolbarItemPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ToolbarItem", ToolbarItem.Props.init,
            casesByKey: [
                "placement": ["automatic", "principal", "confirmationAction", "cancellationAction",
                              "destructiveAction", "primaryAction", "secondaryAction", "topBarLeading",
                              "topBarTrailing", "bottomBar", "keyboard", "navigation", "status",
                              "middle", "Principal", "", 5, true],
            ]
        )
    }
}

@MainActor
final class ToolbarItemGroupPropsValidationTests: PropsValidationTestCase {
    func testMatchesValidation() {
        assertPropsMatchValidation(
            elementType: "ToolbarItemGroup", ToolbarItemGroup.Props.init,
            casesByKey: [
                "placement": ["automatic", "principal", "confirmationAction", "cancellationAction",
                              "destructiveAction", "primaryAction", "secondaryAction", "topBarLeading",
                              "topBarTrailing", "bottomBar", "keyboard", "navigation", "status",
                              "middle", "Principal", "", 5, true],
            ]
        )
    }
}
