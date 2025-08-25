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
    
    func testScrollViewJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ScrollView",
            "content": ["type": "Text", "id": 2, "properties": ["text": "Scrollable content"]],
            "properties": [
                "axis": "vertical",
                "showsIndicators": true
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = ScrollView.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            logger.log("Validated content: \((content as? ViewElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "ScrollView", "Element type should be ScrollView")
            XCTAssertEqual((content as? ViewElement)?.type, "Text", "Content should be Text")
            XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
            XCTAssertEqual((element.properties["axis"] as? String), "vertical", "Axis should be vertical")
            XCTAssertEqual((element.properties["showsIndicators"] as? Bool), true, "ShowsIndicators should be true")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
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
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = ScrollView.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
