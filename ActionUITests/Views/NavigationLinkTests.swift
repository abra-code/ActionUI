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
        
        let model = ActionUIModel.shared
        
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = NavigationLink.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        let destination = element.subviews?["destination"] as? any ActionUIElement
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "NavigationLink", "Element type should be NavigationLink")
        XCTAssertEqual((destination as? ViewElement)?.type, "Text", "Destination should be Text")
        XCTAssertEqual((destination as? ViewElement)?.id, 2, "Destination ID should be 2")
        XCTAssertEqual(element.properties["label"] as? String, "Go to Detail", "Label should be Go to Detail")
        XCTAssertEqual(element.properties["link"] as? String, "detail", "Link should be detail")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        if state.wrappedValue[element.id] == nil {
            logger.log("Warning: State for id \(element.id) is nil", .warning)
        } else if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            logger.log("State dictionary: \(stateDict)", .debug)
        } else {
            XCTFail("State should be a dictionary or nil")
        }
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
