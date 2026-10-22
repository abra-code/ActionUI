// Core/Elements/ButtonCoreTests.swift
/*
 Tests for Button.userTapped, what a tap does on every platform: it fires actionID; it shows the
 popover and fires popoverActionID only when the popover opens, and hides it on the next tap; it
 opens the sheet and the full-screen cover and never closes them; inside a template row, actionID
 names the template's element and the row.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ButtonCoreTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [(actionID: String, viewID: Int, viewPartID: Int)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.setDefaultActionHandler { [weak self] actionID, _, viewID, viewPartID, _ in
            MainActor.assumeIsolated { self?.fired.append((actionID, viewID, viewPartID)) }
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    /// The loaded Button (id 1) and its model.
    private func load(_ json: String) throws -> (ActionUIElement, ViewModel) {
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        return (element, model)
    }

    private func tap(_ element: ActionUIElement, _ model: ViewModel) {
        Button.userTapped(element: element, model: model, windowUUID: windowUUID,
                          props: Button.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model)))
    }

    func testATapFiresTheAction() throws {
        let (element, model) = try load(#"{"type": "Button", "id": 1, "properties": {"title": "Go", "actionID": "go"}}"#)
        tap(element, model)
        XCTAssertEqual(fired.map(\.actionID), ["go"])
        XCTAssertEqual(fired.first?.viewID, 1)
        XCTAssertEqual(fired.first?.viewPartID, 0)
    }

    func testThePopoverTogglesAndItsActionFiresOnlyWhenItOpens() throws {
        let (element, model) = try load(#"""
            {"type": "Button", "id": 1, "properties": {"title": "More", "actionID": "tap", "popoverActionID": "opened"},
             "popover": {"type": "Text", "id": 2, "properties": {"text": "Inside"}}}
            """#)
        tap(element, model)
        XCTAssertEqual(model.states["popoverVisible"] as? Bool, true)
        XCTAssertEqual(fired.map(\.actionID), ["opened", "tap"])
        tap(element, model)
        XCTAssertEqual(model.states["popoverVisible"] as? Bool, false)
        XCTAssertEqual(fired.map(\.actionID), ["opened", "tap", "tap"], "no popover action when it closes")
    }

    func testTheSheetAndCoverOpenAndStayOpen() throws {
        let (element, model) = try load(#"""
            {"type": "Button", "id": 1, "properties": {"title": "Show"},
             "sheet": {"type": "Text", "id": 2, "properties": {"text": "Sheet"}},
             "fullScreenCover": {"type": "Text", "id": 3, "properties": {"text": "Cover"}}}
            """#)
        tap(element, model)
        tap(element, model)
        XCTAssertEqual(model.states["sheetVisible"] as? Bool, true)
        XCTAssertEqual(model.states["fullScreenCoverVisible"] as? Bool, true)
        XCTAssertTrue(fired.isEmpty, "no actionID, no action")
    }

    func testInATemplateRowTheActionNamesTheTemplateAndTheRow() throws {
        let (element, model) = try load(#"{"type": "Button", "id": 1, "properties": {"title": "Row", "actionID": "row"}}"#)
        model.templateContext = TemplateContext(parentID: 7, rowIndex: 3, row: ["a"])
        tap(element, model)
        XCTAssertEqual(fired.first?.viewID, 7)
        XCTAssertEqual(fired.first?.viewPartID, 3)
    }
}
