// Tests/Views/HSplitViewTests.swift
/*
 HSplitViewTests.swift

 Tests for the HSplitView component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class HSplitViewTests: XCTestCase {
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

    func testHSplitViewConstruction() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "HSplitView",
            "properties": {},
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Left"}},
                {"type": "Text", "id": 3, "properties": {"text": "Right"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = HSplitView.validateProperties(element.properties, logger)

        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }

        XCTAssertEqual(children.count, 2, "HSplitView should have 2 children")
        XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ActionUIElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ActionUIElement)?.id, 3, "Second child ID should be 3")
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
    }

    func testHSplitViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "HSplitView",
            "properties": {},
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Left"}},
                {"type": "Text", "id": 3, "properties": {"text": "Right"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "HSplitView", "Element type should be HSplitView")

        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }

        XCTAssertEqual(children.count, 2, "Children should have 2 elements")
        XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Text", "Second child should be Text")
    }

    func testHSplitViewValidatePropertiesEmpty() {
        let properties: [String: Any] = [:]
        let validated = HSplitView.validateProperties(properties, logger)
        // HSplitView has no view-specific properties, validation should pass through
        XCTAssertTrue(validated.isEmpty, "Empty properties should remain empty")
    }

    func testHSplitViewWithFrameConstraints() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "HSplitView",
            "properties": {},
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Sidebar", "frame": {"minWidth": 200, "idealWidth": 250}}},
                {"type": "Text", "id": 3, "properties": {"text": "Detail", "frame": {"maxWidth": ".infinity"}}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = HSplitView.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
    }

    func testHSplitViewNoChildren() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "HSplitView",
            "properties": {}
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = HSplitView.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView even with no children")
    }
}
