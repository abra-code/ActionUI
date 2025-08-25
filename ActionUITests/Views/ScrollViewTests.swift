// Tests/Views/ScrollViewTests.swift
/*
 ScrollViewTests.swift

 Tests for the ScrollView component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for ScrollView:
 {
   "type": "ScrollView",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Scrollable content" }
   },
   "properties": {
     "axis": "vertical",
     "showsIndicators": true
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ScrollViewTests: XCTestCase {
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
    
    func testScrollViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ScrollView",
            "content": {"type": "Text", "id": 2, "properties": {"text": "Scrollable content"}},
            "properties": {
                "axis": "vertical",
                "showsIndicators": true
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
        let validatedProperties = ScrollView.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        let content = element.subviews?["content"] as? any ActionUIElement
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "ScrollView", "Element type should be ScrollView")
        XCTAssertEqual((content as? ViewElement)?.type, "Text", "Content should be Text")
        XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
        XCTAssertEqual(element.properties["axis"] as? String, "vertical", "Axis should be vertical")
        XCTAssertEqual(element.properties["showsIndicators"] as? Bool, true, "ShowsIndicators should be true")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        if state.wrappedValue[element.id] == nil {
            logger.log("Warning: State for id \(element.id) is nil", .warning)
        } else if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            logger.log("State dictionary: \(stateDict)", .debug)
        } else {
            XCTFail("State should be a dictionary or nil")
        }
    }
    
    func testScrollViewMalformedContent() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ScrollView",
            "content": ["id": 2, "properties": ["text": "Scrollable content"]], // Missing type
            "properties": [
                "axis": "vertical"
            ]
        ]
        
        do {
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ViewElement(from: elementDict, logger: consoleLogger)
            let _ = ScrollView.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
