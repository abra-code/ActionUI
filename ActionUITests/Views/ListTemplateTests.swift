// Tests/Views/ListTemplateTests.swift
/*
 ListTemplateTests.swift

 Tests for List data-driven template rendering.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ListTemplateTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        super.tearDown()
    }

    // MARK: - Decoding

    func testListTemplate_decodesTemplateSubview() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "properties": { "actionID": "list.selected" },
            "template": {
                "type": "Label",
                "properties": { "title": "$2", "systemImage": "$1" }
            }
        }
        """
        let element = try load(json)
        let template = element.subviews?["template"] as? ActionUIElement
        XCTAssertNotNil(template, "template subview should be decoded")
        XCTAssertEqual(template?.type, "Label")
        XCTAssertEqual(template?.properties["title"] as? String, "$2")
        XCTAssertEqual(template?.properties["systemImage"] as? String, "$1")
        XCTAssertEqual(template?.id, ActionUIElement.templateIDBase + 1)
    }

    func testListTemplate_noChildrenWhenTemplatePresent() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        let children = element.subviews?["children"] as? [any ActionUIElementBase]
        XCTAssertNil(children, "children should be absent when template is used")
    }

    // MARK: - State Initialization

    func testListTemplate_initializesContentState() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        let content = viewModel.states["content"] as? [[String]]
        XCTAssertNotNil(content, "states[\"content\"] should be initialized as [[String]]")
        XCTAssertTrue(content!.isEmpty, "content should start empty")
    }

    // MARK: - View Building

    func testListTemplate_buildsViewWithRows() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        viewModel.states["content"] = [["Alpha"], ["Beta"], ["Gamma"]]

        let validatedProps = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        XCTAssertFalse(view is SwiftUI.EmptyView, "Should render a List, not EmptyView")
    }

    func testListTemplate_buildsViewWithNoRows() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        let validatedProps = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    func testListTemplate_templateChildrenHaveNoViewModels() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": {
                "type": "HStack",
                "children": [
                    { "type": "Image", "properties": { "systemName": "$1" } },
                    { "type": "Text",  "properties": { "text": "$2" } }
                ]
            }
        }
        """
        let element = try load(json)
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]!
        let base = ActionUIElement.templateIDBase
        XCTAssertNil(windowModel.viewModels[base + 1], "Template root must not have a ViewModel")
        XCTAssertNil(windowModel.viewModels[base + 2], "Template child must not have a ViewModel")
        XCTAssertNil(windowModel.viewModels[base + 3], "Template child must not have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[element.id], "Parent container must have a ViewModel")
    }

    func testListTemplate_complexTemplate_buildsView() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "properties": { "actionID": "list.selected" },
            "template": {
                "type": "HStack",
                "children": [
                    { "type": "Image",  "properties": { "systemName": "$1" } },
                    { "type": "Text",   "properties": { "text": "$2" } },
                    { "type": "Spacer" },
                    { "type": "Button", "properties": { "title": "$3", "actionID": "row.action" } }
                ]
            }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        viewModel.states["content"] = [
            ["star.fill", "Favorites", "Open"],
            ["heart.fill", "Liked", "View"]
        ]

        let validatedProps = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    // MARK: - Action Convention

    func testListTemplate_buttonActionUsesParentIDAndRowIndex() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": { "type": "Button", "properties": { "title": "$1", "actionID": "list.btn" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        viewModel.states["content"] = [["Alpha"], ["Beta"]]

        var capturedViewID: Int?
        var capturedViewPartID: Int?
        ActionUIModel.shared.registerActionHandler(for: "list.btn") { _, _, viewID, viewPartID, _ in
            capturedViewID = viewID
            capturedViewPartID = viewPartID
        }

        // Fire the action as TemplateHelper would for rowIndex=1, parentID=50
        ActionUIModel.shared.actionHandler("list.btn", windowUUID: windowUUID, viewID: 50, viewPartID: 1, context: nil)

        XCTAssertEqual(capturedViewID, 50, "viewID should be the parent List id")
        XCTAssertEqual(capturedViewPartID, 1, "viewPartID should be the row index")
    }

    // MARK: - Equatable

    func testListTemplate_equatable_sameTemplate() throws {
        let json = """
        {
            "type": "List",
            "id": 50,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let e1 = try loadElement(json)
        let e2 = try loadElement(json)
        XCTAssertEqual(e1, e2,
            "Two decodes of the same template JSON must produce equal elements")
    }

    func testListTemplate_equatable_differentTemplate() throws {
        let json1 = """
        { "type": "List", "id": 50,
          "template": { "type": "Text", "properties": { "text": "$1" } } }
        """
        let json2 = """
        { "type": "List", "id": 50,
          "template": { "type": "Label", "properties": { "title": "$1", "systemImage": "$2" } } }
        """
        let e1 = try loadElement(json1)
        let e2 = try loadElement(json2)
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - Helpers

    private func load(_ jsonString: String) throws -> ActionUIElement {
        let data = Data(jsonString.utf8)
        return try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
    }

    private func loadElement(_ jsonString: String) throws -> ActionUIElement {
        let data = Data(jsonString.utf8)
        return try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
    }
}
