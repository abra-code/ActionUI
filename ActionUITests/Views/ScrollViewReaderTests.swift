// Tests/Views/ScrollViewReaderTests.swift
/*
 ScrollViewReaderTests.swift

 Tests for the ScrollViewReader component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for ScrollViewReader:
 {
   "type": "ScrollViewReader",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "ScrollView", "properties": { "content": { "type": "Text", "properties": { "text": "Item 1" } } }
   },
   "properties": {
     "scrollTo": 5,
     "anchor": "top"
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ScrollViewReaderTests: XCTestCase {
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
    
    func testScrollViewReaderJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ScrollViewReader",
            "content": {"type": "ScrollView", "id": 2, "properties": {"content": {"type": "Text", "id": 3, "properties": {"text": "Item 1"}}}},
            "properties": {
                "scrollTo": 5,
                "anchor": "top"
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

        let validatedProperties = ScrollViewReader.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        let content = element.subviews?["content"] as? any ActionUIElementBase
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "ScrollViewReader", "Element type should be ScrollViewReader")
        XCTAssertEqual((content as? ViewElement)?.type, "ScrollView", "Content should be ScrollView")
        XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
        XCTAssertEqual(element.properties.cgFloat(forKey: "scrollTo"), 5.0, "ScrollTo should be 5")
        XCTAssertEqual(element.properties["anchor"] as? String, "top", "Anchor should be top")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testScrollViewReaderMalformedContent() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ScrollViewReader",
            "content": ["id": 2, "properties": ["content": ["type": "Text"]]], // Missing type
            "properties": [
                "scrollTo": 5
            ]
        ]
        
        do {
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ViewElement(from: elementDict, logger: consoleLogger)
            let _ = ScrollViewReader.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElementBase
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
