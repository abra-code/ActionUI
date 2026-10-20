// Tests/Views/ContentUnavailableViewTests.swift
/*
 ContentUnavailableViewTests.swift

 Tests for the ContentUnavailableView component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and search variant.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ContentUnavailableViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // MARK: - Props Tests

    func testPropsValid() {
        let properties: [String: Any] = [
            "title": "No Results",
            "systemImage": "magnifyingglass",
            "description": "Try a different search term."
        ]

        let props = ContentUnavailableView.Props(properties)

        XCTAssertEqual(props.title, "No Results")
        XCTAssertEqual(props.systemImage, "magnifyingglass")
        XCTAssertEqual(props.description, "Try a different search term.")
    }

    func testPropsIgnoreInvalidTypes() {
        let properties: [String: Any] = [
            "title": 123,
            "systemImage": true,
            "description": 456,
            "search": "yes",
            "query": 789
        ]

        let props = ContentUnavailableView.Props(properties)

        XCTAssertEqual(props.title, "No Content", "Invalid title should be the default")
        XCTAssertNil(props.systemImage, "Invalid systemImage should be nil")
        XCTAssertNil(props.description, "Invalid description should be nil")
        XCTAssertFalse(props.search, "Invalid search should be the default")
        XCTAssertEqual(props.query, "", "Invalid query should be the default")
    }

    func testPropsSearchVariant() {
        let properties: [String: Any] = [
            "search": true,
            "query": "planets"
        ]

        let props = ContentUnavailableView.Props(properties)

        XCTAssertTrue(props.search)
        XCTAssertEqual(props.query, "planets")
    }

    func testPropsEmpty() {
        let properties: [String: Any] = [:]

        let props = ContentUnavailableView.Props(properties)

        XCTAssertEqual(props.title, "No Content")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.description)
        XCTAssertFalse(props.search)
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
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

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
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

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
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

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
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        viewModel.value = ContentUnavailableView.initialValue(viewModel)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

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
