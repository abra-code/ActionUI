// Core/Elements/TablePropsTests.swift
/*
 Tests for Table.Props: the column headers, the per-column cell types (padded to one entry per
 column), the widths, the headers visibility and the actions. The fallbacks that the renderer used
 to decide per cell are checked here: an Image cell without a known interpretation is systemName,
 a Button cell reads only known interpretations, a Toggle's disabledColumn must be 1 or more.
*/

import XCTest
@testable import ActionUI

final class TablePropsTests: XCTestCase {

    func testDefaults() {
        let props = Table.Props([:])
        XCTAssertEqual(props.columns, [])
        XCTAssertEqual(props.columnTypes, [])
        XCTAssertNil(props.widths)
        XCTAssertNil(props.minWidths)
        XCTAssertNil(props.columnHeadersVisibility)
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.doubleClickActionID)
    }

    func testValidValues() {
        let props = Table.Props([
            "columns": ["Name", "Action", "Icon"] as [Any],
            "columnTypes": [
                ["viewType": "Text"],
                ["viewType": "Button", "actionContext": "rowIndex", "actionID": "row.action"],
                ["viewType": "Image", "dataInterpretation": "path"],
            ] as [Any],
            "widths": [100, 80, 40] as [Any],
            "minWidths": [80, 60, 30] as [Any],
            "columnHeadersVisibility": "hidden",
            "actionID": "table.selection.changed",
            "doubleClickActionID": "table.double.click",
        ])
        XCTAssertEqual(props.columns, ["Name", "Action", "Icon"])
        XCTAssertEqual(props.columnTypes.map(\.viewType), [.text, .button, .image])
        XCTAssertEqual(props.columnTypes[1].actionContext, .rowIndex)
        XCTAssertEqual(props.columnTypes[1].actionID, "row.action")
        XCTAssertEqual(props.columnTypes[2].dataInterpretation, .path)
        XCTAssertEqual(props.widths, [100, 80, 40])
        XCTAssertEqual(props.minWidths, [80, 60, 30])
        XCTAssertEqual(props.columnHeadersVisibility, .hidden)
        XCTAssertEqual(props.actionID, "table.selection.changed")
        XCTAssertEqual(props.doubleClickActionID, "table.double.click")
    }

    func testColumnsThatAreNotStringsAreNoColumns() {
        XCTAssertEqual(Table.Props(["columns": ["A", 5] as [Any]]).columns, [])
        XCTAssertEqual(Table.Props(["columns": "A"]).columns, [])
    }

    func testColumnTypesArePaddedToTheColumnsAsText() {
        let props = Table.Props(["columns": ["A", "B", "C"] as [Any], "columnTypes": [["viewType": "Toggle"]] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.viewType), [.toggle, .text, .text])
        XCTAssertEqual(Table.Props(["columns": ["A", "B"] as [Any]]).columnTypes.map(\.viewType), [.text, .text])
    }

    func testColumnTypesBeyondTheColumnsAreKept() {
        let props = Table.Props(["columns": ["A"] as [Any], "columnTypes": [["viewType": "Button"], ["viewType": "Toggle"]] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.viewType), [.button, .toggle])
    }

    func testColumnTypesWithAnEntryThatIsNotADictionaryAreNone() {
        let props = Table.Props(["columns": ["A", "B"] as [Any], "columnTypes": [["viewType": "Button"], "Toggle"] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.viewType), [.text, .text])
        XCTAssertEqual(Table.Props(["columnTypes": "Text"]).columnTypes, [])
    }

    func testViewTypeThatIsUnknownOrNotAStringIsText() {
        let props = Table.Props(["columnTypes": [
            ["viewType": "Fancy"], ["viewType": 5], ["viewType": "text"], [String: Any](),
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.viewType), [.text, .text, .text, .text])
    }

    func testEveryViewTypeName() {
        let props = Table.Props(["columnTypes": [
            ["viewType": "Text"], ["viewType": "Button"], ["viewType": "Image"],
            ["viewType": "AsyncImage"], ["viewType": "Toggle"],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.viewType), [.text, .button, .image, .asyncImage, .toggle])
    }

    func testImageInterpretationIsSystemNameWhenMissingOrUnknown() {
        let props = Table.Props(["columnTypes": [
            ["viewType": "Image"],
            ["viewType": "Image", "dataInterpretation": "bogus"],
            ["viewType": "Image", "dataInterpretation": 5],
            ["viewType": "Image", "dataInterpretation": "path"],
            ["viewType": "Image", "dataInterpretation": "mixed"],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.dataInterpretation), [.systemName, .systemName, .systemName, .path, .mixed])
    }

    func testEveryInterpretationName() {
        for name in ["path", "systemName", "assetName", "resourceName", "mixed"] {
            let props = Table.Props(["columnTypes": [
                ["viewType": "Image", "dataInterpretation": name],
                ["viewType": "Button", "dataInterpretation": name],
            ] as [Any]])
            XCTAssertEqual(props.columnTypes[0].dataInterpretation?.rawValue, name)
            XCTAssertEqual(props.columnTypes[1].dataInterpretation?.rawValue, name)
        }
    }

    func testButtonInterpretationIsKnownNamesOnly() {
        // A Button cell with no known interpretation is a text button, not an image.
        let props = Table.Props(["columnTypes": [
            ["viewType": "Button"],
            ["viewType": "Button", "dataInterpretation": "bogus"],
            ["viewType": "Button", "dataInterpretation": 5],
            ["viewType": "Button", "dataInterpretation": "assetName"],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.dataInterpretation), [nil, nil, nil, .assetName])
    }

    func testButtonActionContext() {
        let props = Table.Props(["columnTypes": [
            ["viewType": "Button"],
            ["viewType": "Button", "actionContext": "title"],
            ["viewType": "Button", "actionContext": "rowIndex"],
            ["viewType": "Button", "actionContext": "columnIndex"],
            ["viewType": "Button", "actionContext": "rowColumnIndex"],
            ["viewType": "Button", "actionContext": "bogus"],
            ["viewType": "Button", "actionContext": 5],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.actionContext), [.title, .title, .rowIndex, .columnIndex, .rowColumnIndex, .title, .title])
    }

    func testCellActionID() {
        let props = Table.Props(["columnTypes": [
            ["viewType": "Button", "actionID": "go"],
            ["viewType": "Toggle", "actionID": "toggled"],
            ["viewType": "Button", "actionID": 5],
            ["viewType": "Button"],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.actionID), ["go", "toggled", nil, nil])
    }

    func testToggleStyle() {
        let props = Table.Props(["columnTypes": [
            ["viewType": "Toggle"],
            ["viewType": "Toggle", "style": "checkbox"],
            ["viewType": "Toggle", "style": "switch"],
            ["viewType": "Toggle", "style": "button"],
            ["viewType": "Toggle", "style": "bogus"],
            ["viewType": "Toggle", "style": 5],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.toggleStyle), [.checkbox, .checkbox, .switch, .button, .checkbox, .checkbox])
    }

    func testToggleDisabledColumnMustBeOneOrMore() {
        // Below 1 would index before the first column of the row: it is no disabling column.
        let props = Table.Props(["columnTypes": [
            ["viewType": "Toggle"],
            ["viewType": "Toggle", "disabledColumn": 1],
            ["viewType": "Toggle", "disabledColumn": 4],
            ["viewType": "Toggle", "disabledColumn": 0],
            ["viewType": "Toggle", "disabledColumn": -2],
            ["viewType": "Toggle", "disabledColumn": 2.0],
            ["viewType": "Toggle", "disabledColumn": "2"],
        ] as [Any]])
        XCTAssertEqual(props.columnTypes.map(\.disabledColumn), [nil, 1, 4, nil, nil, nil, nil])
    }

    func testWidthsAreAnArrayOfIntAndNothingElse() {
        XCTAssertEqual(Table.Props(["widths": [100, 80] as [Any]]).widths, [100, 80])
        XCTAssertEqual(Table.Props(["widths": [Any]()]).widths, [])
        XCTAssertNil(Table.Props(["widths": [100.5, 80] as [Any]]).widths)
        XCTAssertNil(Table.Props(["widths": [100, "80"] as [Any]]).widths)
        XCTAssertNil(Table.Props(["widths": 100]).widths)
        XCTAssertEqual(Table.Props(["minWidths": [10] as [Any]]).minWidths, [10])
        XCTAssertNil(Table.Props(["minWidths": [10.5] as [Any]]).minWidths)
        XCTAssertNil(Table.Props(["minWidths": "10"]).minWidths)
    }

    func testColumnHeadersVisibility() {
        for name in ["visible", "hidden", "automatic"] {
            XCTAssertEqual(Table.Props(["columnHeadersVisibility": name]).columnHeadersVisibility?.rawValue, name)
        }
        XCTAssertNil(Table.Props(["columnHeadersVisibility": "gone"]).columnHeadersVisibility)
        XCTAssertNil(Table.Props(["columnHeadersVisibility": "Hidden"]).columnHeadersVisibility)
        XCTAssertNil(Table.Props(["columnHeadersVisibility": 5]).columnHeadersVisibility)
    }

    func testActionsThatAreNotStringsAreNil() {
        let props = Table.Props(["actionID": 5, "doubleClickActionID": 6])
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.doubleClickActionID)
    }
}
