// Tests/Views/NavigationLinkTests.swift
/*
 NavigationLinkTests.swift

 Tests for the NavigationLink component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "title": "Go to Detail",
     "link": "detail"
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class NavigationLinkTests: XCTestCase {
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
    
    func testNavigationLinkJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationLink",
            "destination": {"type": "Text", "id": 2, "properties": {"text": "Detail"}},
            "properties": {
                "title": "Go to Detail",
                "link": "detail"
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

        let validatedProperties = NavigationLink.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        let destination = element.subviews?["destination"] as? any ActionUIElementBase
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "NavigationLink", "Element type should be NavigationLink")
        XCTAssertEqual((destination as? ActionUIElement)?.type, "Text", "Destination should be Text")
        XCTAssertEqual((destination as? ActionUIElement)?.id, 2, "Destination ID should be 2")
        XCTAssertEqual(element.properties["title"] as? String, "Go to Detail", "Label should be Go to Detail")
        XCTAssertEqual(element.properties["link"] as? String, "detail", "Link should be detail")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testNavigationLinkMalformedDestination() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationLink",
            "destination": ["id": 2, "properties": ["text": "Detail"]], // Missing type
            "properties": [
                "title": "Go to Detail",
                "link": "detail"
            ]
        ]

        do {
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
            let _ = NavigationLink.validateProperties(element.properties, logger)
            let destination = element.subviews?["destination"] as? any ActionUIElementBase
            XCTAssertNil(destination, "Malformed destination should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }

    // MARK: - Form 2 (destinationViewId) tests

    func testNavigationLinkForm2DestinationViewId() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationLink",
            "properties": {
                "title": "Go to Detail",
                "destinationViewId": 10
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

        XCTAssertEqual(element.properties["title"] as? String, "Go to Detail")
        XCTAssertEqual(viewModel.validatedProperties["destinationViewId"] as? Int, 10, "destinationViewId should be validated as Int")
        XCTAssertNil(element.subviews?["destination"], "No inline destination should be present")

        // initialValue should return the destinationViewId
        let initialValue = NavigationLink.initialValue(viewModel)
        XCTAssertEqual(initialValue as? Int, 10, "initialValue should return destinationViewId Int")
    }

    func testNavigationLinkForm2BuildView() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationLink",
            "properties": [
                "title": "Go to Detail",
                "destinationViewId": 10
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = ActionUIRegistry.shared.getValidatedProperties(element: element, model: viewModel)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        XCTAssertNotNil(view, "buildView should succeed for Form 2 NavigationLink with destinationViewId")
    }

    func testNavigationLinkValidatePropertiesTitle() throws {
        // Valid title
        let validProps: [String: Any] = ["title": "My Link"]
        let validated = NavigationLink.validateProperties(validProps, logger)
        XCTAssertEqual(validated["title"] as? String, "My Link", "Valid string title should be preserved")

        // Invalid title type
        let invalidProps: [String: Any] = ["title": 123]
        let validated2 = NavigationLink.validateProperties(invalidProps, logger)
        XCTAssertNil(validated2["title"], "Non-string title should be nil")
    }
}
