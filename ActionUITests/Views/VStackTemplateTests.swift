// Tests/Views/VStackTemplateTests.swift
/*
 VStackTemplateTests.swift

 Tests for VStack data-driven template rendering.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class VStackTemplateTests: XCTestCase {
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

    func testVStackTemplate_decodesTemplateSubview() throws {
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "properties": { "spacing": 8 },
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
        // No explicit id in JSON → normalized to templateIDBase+1 (first element DFS)
        XCTAssertEqual(template?.id, ActionUIElement.templateIDBase + 1)
    }

    func testVStackTemplate_noChildrenWhenTemplatePresent() throws {
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        let children = element.subviews?["children"] as? [any ActionUIElementBase]
        XCTAssertNil(children, "children should be absent when template is used")
    }

    // MARK: - State Initialization

    func testVStackTemplate_initializesContentState() throws {
        let json = """
        {
            "type": "VStack",
            "id": 10,
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

    func testVStackWithChildren_doesNotInitializeContentState() throws {
        let json = """
        {
            "type": "VStack",
            "id": 5,
            "children": [
                { "type": "Text", "id": 6, "properties": { "text": "Static" } }
            ]
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        XCTAssertNil(viewModel.states["content"],
                     "states[\"content\"] should NOT be set for non-template VStack")
    }

    // MARK: - View Building

    func testVStackTemplate_buildsViewWithRows() throws {
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        viewModel.states["content"] = [["Alpha"], ["Beta"], ["Gamma"]]

        let validatedProps = VStack.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        XCTAssertFalse(view is SwiftUI.EmptyView, "Should render a VStack, not EmptyView")
    }

    func testVStackTemplate_buildsViewWithNoRows() throws {
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        let validatedProps = VStack.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        // Empty rows → VStack renders with no children, still a VStack (not EmptyView)
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    func testVStackTemplate_templateChildrenHaveNoViewModels() throws {
        let json = """
        {
            "type": "VStack",
            "id": 10,
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
        // After normalization, template IDs are in the Int.min range.
        // None of these must have ViewModels — they are stateless blueprints.
        let base = ActionUIElement.templateIDBase
        XCTAssertNil(windowModel.viewModels[base + 1], "Template root must not have a ViewModel")
        XCTAssertNil(windowModel.viewModels[base + 2], "Template child must not have a ViewModel")
        XCTAssertNil(windowModel.viewModels[base + 3], "Template child must not have a ViewModel")
        // The parent (id=10) DOES have a ViewModel
        XCTAssertNotNil(windowModel.viewModels[element.id], "Parent container must have a ViewModel")
    }

    // MARK: - Equatable

    func testVStackTemplate_equatable_sameTemplate_noExplicitIDs() throws {
        // Template elements without explicit ids must still compare equal across two decodes.
        // normalizeTemplateIDs replaces auto-generated (negative) ids with deterministic ordinals.
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let e1 = try loadElement(json)
        let e2 = try loadElement(json)
        XCTAssertEqual(e1, e2,
            "Two decodes of the same template JSON must produce equal elements regardless of auto-generated IDs")
    }

    func testVStackTemplate_equatable_sameTemplate_withExplicitIDs() throws {
        // Explicit positive ids are preserved by normalizeTemplateIDs.
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": { "type": "Text", "id": 500, "properties": { "text": "$1" } }
        }
        """
        let e1 = try loadElement(json)
        let e2 = try loadElement(json)
        XCTAssertEqual(e1, e2)
        let template = e1.subviews?["template"] as? ActionUIElement
        XCTAssertEqual(template?.id, 500, "Explicit positive ID must be preserved by normalization")
    }

    func testVStackTemplate_equatable_differentTemplate() throws {
        let json1 = """
        { "type": "VStack", "id": 10,
          "template": { "type": "Text", "properties": { "text": "$1" } } }
        """
        let json2 = """
        { "type": "VStack", "id": 10,
          "template": { "type": "Label", "properties": { "title": "$1", "systemImage": "$2" } } }
        """
        let e1 = try loadElement(json1)
        let e2 = try loadElement(json2)
        XCTAssertNotEqual(e1, e2)
    }

    func testVStackTemplate_normalizedIDs_areInTemplateRange() throws {
        // Auto-generated template IDs must be normalized to templateIDBase+ordinal (DFS order),
        // placing them far from the live-view auto-generated range (which counts down from -1).
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": {
                "type": "HStack",
                "children": [
                    { "type": "Text",   "properties": { "text": "$1" } },
                    { "type": "Button", "properties": { "title": "$2", "actionID": "x" } }
                ]
            }
        }
        """
        let base = ActionUIElement.templateIDBase
        let element = try loadElement(json)
        let template = element.subviews?["template"] as? ActionUIElement
        XCTAssertEqual(template?.id, base + 1, "Template root gets templateIDBase+1")
        let children = template?.subviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(children?[0].id, base + 2, "First child gets templateIDBase+2")
        XCTAssertEqual(children?[1].id, base + 3, "Second child gets templateIDBase+3")
    }

    func testVStackTemplate_normalizedIDs_neverCollideWithLiveViewIDs() throws {
        // Template IDs (Int.min range) must never equal any auto-generated live-view ID
        // (which counts down from -1). Verify that all template IDs are < any plausible live-view ID.
        let json = """
        {
            "type": "VStack",
            "id": 10,
            "template": {
                "type": "HStack",
                "children": [
                    { "type": "Text", "properties": { "text": "$1" } }
                ]
            }
        }
        """
        let element = try loadElement(json)
        let template = element.subviews?["template"] as? ActionUIElement
        let children = template?.subviews?["children"] as? [ActionUIElement]
        let allTemplateIDs = [template?.id, children?.first?.id].compactMap { $0 }
        // All template IDs must be in the Int.min range (< -1_000_000_000 as a conservative bound)
        for id in allTemplateIDs {
            XCTAssertLessThan(id, -1_000_000_000,
                "Template id \(id) must be far from the live-view auto-generated range")
        }
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
