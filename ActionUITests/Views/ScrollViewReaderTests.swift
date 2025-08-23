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
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        super.tearDown()
    }
    
    func testScrollViewReaderJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ScrollViewReader",
            "content": ["type": "ScrollView", "id": 2, "properties": ["content": ["type": "Text", "id": 3, "properties": ["text": "Item 1"]]]],
            "properties": [
                "scrollTo": 5,
                "anchor": "top"
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict)
            let _ = ScrollViewReader.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            logger.log("content: \((content as? ViewElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "ScrollViewReader", "Element type should be ScrollViewReader")
            XCTAssertEqual((content as? ViewElement)?.type, "ScrollView", "Content should be ScrollView")
            XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
            XCTAssertEqual((element.properties["scrollTo"] as? Int), 5, "ScrollTo should be 5")
            XCTAssertEqual((element.properties["anchor"] as? String), "top", "Anchor should be top")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
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
            let element = try ViewElement(from: elementDict)
            let _ = ScrollViewReader.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
