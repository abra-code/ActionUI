// Core/Elements/ListPropsTests.swift
/*
 Tests for List.Props: the homogeneous cell (itemType), the actions, the list style and the row
 styling.
*/

import XCTest
@testable import ActionUI

final class ListPropsTests: XCTestCase {

    func testDefaults() {
        let props = List.Props([:])
        XCTAssertEqual(props.viewType, .text)
        XCTAssertEqual(props.dataInterpretation, .systemName)
        XCTAssertEqual(props.actionContext, .title)
        XCTAssertNil(props.itemActionID)
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.doubleClickActionID)
        XCTAssertNil(props.onRefreshActionID)
        XCTAssertNil(props.listStyle)
        XCTAssertNil(props.rowBackground)
        XCTAssertNil(props.rowSeparator)
        XCTAssertNil(props.rowSeparatorTint)
        XCTAssertNil(props.rowInsets)
        XCTAssertFalse(props.hasRowModifiers)
    }

    func testItemType() {
        let button = List.Props(["itemType": ["viewType": "Button", "actionContext": "rowIndex", "actionID": "clicked"]])
        XCTAssertEqual(button.viewType, .button)
        XCTAssertEqual(button.actionContext, .rowIndex)
        XCTAssertEqual(button.itemActionID, "clicked")

        let image = List.Props(["itemType": ["viewType": "Image", "dataInterpretation": "path"]])
        XCTAssertEqual(image.viewType, .image)
        XCTAssertEqual(image.dataInterpretation, .path)

        XCTAssertEqual(List.Props(["itemType": ["viewType": "AsyncImage"]]).viewType, .asyncImage)
    }

    func testItemTypeFallbacks() {
        // A one-column item has nowhere to hold both a title and a state: Toggle is Text.
        XCTAssertEqual(List.Props(["itemType": ["viewType": "Toggle"]]).viewType, .text)
        XCTAssertEqual(List.Props(["itemType": ["viewType": "Fancy"]]).viewType, .text)
        XCTAssertEqual(List.Props(["itemType": "Button"]).viewType, .text)
        XCTAssertEqual(List.Props(["itemType": ["viewType": "Image", "dataInterpretation": "bogus"]]).dataInterpretation, .systemName)
        XCTAssertEqual(List.Props(["itemType": ["viewType": "Button", "actionContext": "bogus"]]).actionContext, .title)
    }

    func testActions() {
        let props = List.Props(["actionID": "selected", "doubleClickActionID": "opened", "onRefreshActionID": "refresh"])
        XCTAssertEqual(props.actionID, "selected")
        XCTAssertEqual(props.doubleClickActionID, "opened")
        XCTAssertEqual(props.onRefreshActionID, "refresh")
        XCTAssertNil(List.Props(["doubleClickActionID": 5]).doubleClickActionID)
    }

    func testListStylesKeepEveryNameWhateverThePlatform() {
        for style in List.Props.ListStyle.allCases {
            XCTAssertEqual(List.Props(["listStyle": style.rawValue]).listStyle, style)
        }
        XCTAssertNil(List.Props(["listStyle": "fancy"]).listStyle)
    }

    func testRowStyling() {
        let props = List.Props([
            "listRowBackground": "blue", "listRowSeparator": "hidden", "listRowSeparatorTint": "gray", "listRowInsets": 16,
        ])
        XCTAssertEqual(props.rowBackground, "blue")
        XCTAssertEqual(props.rowSeparator, .hidden)
        XCTAssertEqual(props.rowSeparatorTint, "gray")
        XCTAssertEqual(props.rowInsets, .uniform(16))
        XCTAssertTrue(props.hasRowModifiers)
    }

    func testRowInsets() {
        XCTAssertEqual(List.Props(["listRowInsets": 16.5]).rowInsets, .uniform(16.5))
        XCTAssertEqual(List.Props(["listRowInsets": ["top": 8]]).rowInsets, .edges(top: 8, leading: 0, bottom: 0, trailing: 0))
        XCTAssertEqual(List.Props(["listRowInsets": [String: Any]()]).rowInsets, .edges(top: 0, leading: 0, bottom: 0, trailing: 0))
        XCTAssertNil(List.Props(["listRowInsets": "16"]).rowInsets)
        XCTAssertNil(List.Props(["listRowInsets": [1] as [Any]]).rowInsets)
    }

    func testUnusableRowStylingIsNoRowStyling() {
        let props = List.Props(["listRowBackground": 5, "listRowSeparator": "bogus", "listRowSeparatorTint": 5, "listRowInsets": "16"])
        XCTAssertFalse(props.hasRowModifiers)
    }
}
