// Tests/Views/LabeledContentTests.swift
/*
 LabeledContentTests.swift

 Tests for the LabeledContent component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and child view handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LabeledContentTests: XCTestCase {
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

    func testLabeledContentValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Username",
            "padding": 10.0
        ]

        let validated = ActionUI.LabeledContent.validateProperties(properties, logger)

        XCTAssertEqual(validated["title"] as? String, "Username", "title should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }

    func testLabeledContentValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123
        ]

        let validated = ActionUI.LabeledContent.validateProperties(properties, logger)

        XCTAssertNil(validated["title"], "Invalid title should be nil")
    }

    func testLabeledContentValidatePropertiesMissing() {
        let properties: [String: Any] = [:]

        let validated = ActionUI.LabeledContent.validateProperties(properties, logger)

        XCTAssertNil(validated["title"], "Missing title should be nil")
    }

    func testLabeledContentConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LabeledContent",
            "properties": [
                "title": "Username",
                "padding": 10.0
            ],
            "children": [
                ["type": "TextField", "id": 2, "properties": ["prompt": "Enter username"]]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ActionUI.LabeledContent.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }

    func testLabeledContentConstructionWithMultipleChildren() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LabeledContent",
            "properties": [
                "title": "Credentials"
            ],
            "children": [
                ["type": "TextField", "id": 2, "properties": ["prompt": "Username"]],
                ["type": "SecureField", "id": 3, "properties": ["prompt": "Password"]]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ActionUI.LabeledContent.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }
        XCTAssertEqual(children.count, 2, "LabeledContent should have 2 children")
    }

    func testLabeledContentConstructionWithoutTitle() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LabeledContent",
            "properties": [:],
            "children": [
                ["type": "TextField", "id": 2, "properties": ["prompt": "Enter text"]]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ActionUI.LabeledContent.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }

    func testLabeledContentJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "LabeledContent",
            "properties": {
                "title": "Username",
                "padding": 10.0
            },
            "children": [
                {"type": "TextField", "id": 2, "properties": {"prompt": "Enter username"}}
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
        XCTAssertEqual(element.type, "LabeledContent", "Element type should be LabeledContent")
        XCTAssertEqual(element.properties["title"] as? String, "Username", "title should be Username")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")

        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
            XCTAssertEqual(children.count, 1, "Should have one child")
            XCTAssertEqual(children[0].type, "TextField", "Child type should be TextField")
            XCTAssertEqual(children[0].id, 2, "Child ID should be 2")
        } else {
            XCTFail("Children should be valid array")
        }

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.value, "Initial viewModel value should be nil for LabeledContent")
    }
}
