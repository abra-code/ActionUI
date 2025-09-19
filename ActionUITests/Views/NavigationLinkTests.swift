// Tests/Views/NavigationLinkTests.swift
/*
 NavigationLinkTests.swift

 Tests for the NavigationLink component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "label": "Go to Detail",
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
        ActionUIModel.shared.setLogger(logger)
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
                "label": "Go to Detail",
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
        
        let destination = element.subviews?["destination"] as? any ActionUIElement
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "NavigationLink", "Element type should be NavigationLink")
        XCTAssertEqual((destination as? ViewElement)?.type, "Text", "Destination should be Text")
        XCTAssertEqual((destination as? ViewElement)?.id, 2, "Destination ID should be 2")
        XCTAssertEqual(element.properties["label"] as? String, "Go to Detail", "Label should be Go to Detail")
        XCTAssertEqual(element.properties["link"] as? String, "detail", "Link should be detail")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testNavigationLinkMalformedDestination() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationLink",
            "destination": ["id": 2, "properties": ["text": "Detail"]], // Missing type
            "properties": [
                "label": "Go to Detail",
                "link": "detail"
            ]
        ]
        
        do {
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ViewElement(from: elementDict, logger: consoleLogger)
            let _ = NavigationLink.validateProperties(element.properties, logger)
            let destination = element.subviews?["destination"] as? any ActionUIElement
            XCTAssertNil(destination, "Malformed destination should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
