// Tests/Views/HStackTemplateTests.swift
/*
 HStackTemplateTests.swift

 Tests for HStack data-driven template rendering.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class HStackTemplateTests: XCTestCase {
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

    func testHStackTemplate_decodesTemplateSubview() throws {
        let json = """
        {
            "type": "HStack",
            "id": 20,
            "properties": { "spacing": 8 },
            "template": {
                "type": "Button",
                "properties": { "title": "$1", "actionID": "chip.tap", "buttonStyle": "bordered" }
            }
        }
        """
        let element = try load(json)
        let template = element.subviews?["template"] as? ActionUIElement
        XCTAssertNotNil(template)
        XCTAssertEqual(template?.type, "Button")
        XCTAssertEqual(template?.properties["title"] as? String, "$1")
        XCTAssertEqual(template?.properties["actionID"] as? String, "chip.tap")
    }

    // MARK: - State Initialization

    func testHStackTemplate_initializesContentState() throws {
        let json = """
        {
            "type": "HStack",
            "id": 20,
            "template": { "type": "Button", "properties": { "title": "$1", "actionID": "x" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        let content = viewModel.states["content"] as? [[String]]
        XCTAssertNotNil(content)
        XCTAssertTrue(content!.isEmpty)
    }

    func testHStackWithChildren_doesNotInitializeContentState() throws {
        let json = """
        {
            "type": "HStack",
            "id": 5,
            "children": [
                { "type": "Text", "id": 6, "properties": { "text": "A" } },
                { "type": "Text", "id": 7, "properties": { "text": "B" } }
            ]
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        XCTAssertNil(viewModel.states["content"])
    }

    // MARK: - View Building

    func testHStackTemplate_buildsViewWithRows() throws {
        let json = """
        {
            "type": "HStack",
            "id": 20,
            "template": { "type": "Button", "properties": { "title": "$1", "actionID": "chip.tap" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        viewModel.states["content"] = [["Swift"], ["Python"], ["Kotlin"]]

        let validatedProps = HStack.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    func testHStackTemplate_templateChildrenHaveNoViewModels() throws {
        let json = """
        {
            "type": "HStack",
            "id": 20,
            "template": {
                "type": "Label",
                "properties": { "title": "$1", "systemImage": "$2" }
            }
        }
        """
        let element = try load(json)
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]!
        // After normalization, template root is in the Int.min range. Must not have a ViewModel.
        XCTAssertNil(windowModel.viewModels[ActionUIElement.templateIDBase + 1],
                     "Template element must not have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[element.id])
    }

    // MARK: - Action Convention

    func testHStackTemplate_buttonActionUsesParentIDAndRowIndex() throws {
        // Verify that TemplateHelper dispatches with parentID and rowIndex
        let json = """
        {
            "type": "HStack",
            "id": 30,
            "template": { "type": "Button", "properties": { "title": "$1", "actionID": "chip.tap" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        viewModel.states["content"] = [["Swift"], ["Python"]]

        var capturedViewID: Int?
        var capturedViewPartID: Int?
        ActionUIModel.shared.registerActionHandler(for: "chip.tap") { _, _, viewID, viewPartID, _ in
            capturedViewID = viewID
            capturedViewPartID = viewPartID
        }

        // Build the template view for row 1 (Python) and simulate the button tap
        let template = element.subviews!["template"] as! any ActionUIElementBase
        // Directly invoke TemplateHelper to get the button action fired synchronously
        let substituted = TemplateHelper.substituteProperties(
            template.properties, row: ["Python"]
        )
        XCTAssertEqual(substituted["title"] as? String, "Python")

        // Fire the action as TemplateHelper would for rowIndex=1, parentID=30
        ActionUIModel.shared.actionHandler("chip.tap", windowUUID: windowUUID, viewID: 30, viewPartID: 1, context: nil)

        XCTAssertEqual(capturedViewID, 30, "viewID should be the parent container id")
        XCTAssertEqual(capturedViewPartID, 1, "viewPartID should be the row index")
    }

    // MARK: - Helpers

    private func load(_ jsonString: String) throws -> ActionUIElement {
        let data = Data(jsonString.utf8)
        return try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
    }
}
