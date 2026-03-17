// Tests/Views/ContentUnavailableViewTests.swift
/*
 ContentUnavailableViewTests.swift

 Tests for the ContentUnavailableView component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and search variant.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ContentUnavailableViewTests: XCTestCase {
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

    // MARK: - Validation Tests

    func testValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "No Results",
            "systemImage": "magnifyingglass",
            "description": "Try a different search term."
        ]

        let validated = ContentUnavailableView.validateProperties(properties, logger)

        XCTAssertEqual(validated["title"] as? String, "No Results")
        XCTAssertEqual(validated["systemImage"] as? String, "magnifyingglass")
        XCTAssertEqual(validated["description"] as? String, "Try a different search term.")
    }

    func testValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = [
            "title": 123,
            "systemImage": true,
            "description": 456,
            "search": "yes",
            "query": 789
        ]

        let validated = ContentUnavailableView.validateProperties(properties, logger)

        XCTAssertNil(validated["title"], "Invalid title should be nil")
        XCTAssertNil(validated["systemImage"], "Invalid systemImage should be nil")
        XCTAssertNil(validated["description"], "Invalid description should be nil")
        XCTAssertNil(validated["search"], "Invalid search should be nil")
        XCTAssertNil(validated["query"], "Invalid query should be nil")
    }

    func testValidatePropertiesSearchVariant() {
        let properties: [String: Any] = [
            "search": true,
            "query": "planets"
        ]

        let validated = ContentUnavailableView.validateProperties(properties, logger)

        XCTAssertEqual(validated["search"] as? Bool, true)
        XCTAssertEqual(validated["query"] as? String, "planets")
    }

    func testValidatePropertiesEmpty() {
        let properties: [String: Any] = [:]

        let validated = ContentUnavailableView.validateProperties(properties, logger)

        XCTAssertNil(validated["title"])
        XCTAssertNil(validated["systemImage"])
        XCTAssertNil(validated["description"])
        XCTAssertNil(validated["search"])
    }

    // MARK: - Construction Tests

    func testConstructionWithAllProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ContentUnavailableView",
            "properties": [
                "title": "No Favorites",
                "systemImage": "star.slash",
                "description": "Items you mark as favorite will appear here."
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ContentUnavailableView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(viewModel.value as? String, "No Favorites")
    }

    func testConstructionSearchVariant() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ContentUnavailableView",
            "properties": [
                "search": true,
                "query": "planets"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ContentUnavailableView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(viewModel.value as? String, "planets")
    }

    func testConstructionSearchVariantEmptyQuery() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ContentUnavailableView",
            "properties": [
                "search": true
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ContentUnavailableView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(viewModel.value as? String, "")
    }

    func testConstructionTitleOnly() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ContentUnavailableView",
            "properties": [
                "title": "Nothing Here"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ContentUnavailableView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(viewModel.value as? String, "Nothing Here")
    }

    // MARK: - JSON Decoding Tests

    func testJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ContentUnavailableView",
            "properties": {
                "title": "No Internet",
                "systemImage": "wifi.slash",
                "description": "Check your connection."
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "ContentUnavailableView")
        XCTAssertEqual(element.properties["title"] as? String, "No Internet")
        XCTAssertEqual(element.properties["systemImage"] as? String, "wifi.slash")
        XCTAssertEqual(element.properties["description"] as? String, "Check your connection.")
    }

    func testJSONDecodingSearchVariant() throws {
        let jsonString = """
        {
            "id": 2,
            "type": "ContentUnavailableView",
            "properties": {
                "search": true,
                "query": "test query"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 2)
        XCTAssertEqual(element.type, "ContentUnavailableView")
        XCTAssertEqual(element.properties["search"] as? Bool, true)
        XCTAssertEqual(element.properties["query"] as? String, "test query")
    }

    // MARK: - Value Update Tests

    func testValueUpdateViaModel() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ContentUnavailableView",
            "properties": {
                "title": "Original Title",
                "systemImage": "exclamationmark.triangle"
            }
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

        let _ = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID).body

        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Updated Title")
        let updatedValue = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Updated Title")
    }
}
