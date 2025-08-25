// Tests/Views/TabBarItemTests.swift
/*
 TabBarItemTests.swift

 Tests for the TabBarItem component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for TabBarItem:
 {
   "type": "TabBarItem",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "properties": {
     "title": "Home",
     "systemImage": "house"
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TabBarItemTests: XCTestCase {
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
    
    func testTabBarItemJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TabBarItem",
            "content": ["type": "Text", "id": 2, "properties": ["text": "Home"]],
            "properties": [
                "title": "Home",
                "systemImage": "house"
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = TabBarItem.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            logger.log("Validated content: \((content as? ViewElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "TabBarItem", "Element type should be TabBarItem")
            XCTAssertEqual((content as? ViewElement)?.type, "Text", "Content should be Text")
            XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
            XCTAssertEqual((element.properties["title"] as? String), "Home", "Title should be Home")
            XCTAssertEqual((element.properties["systemImage"] as? String), "house", "SystemImage should be house")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
    
    func testTabBarItemMalformedContent() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TabBarItem",
            "content": ["id": 2, "properties": ["text": "Home"]], // Missing type
            "properties": [
                "title": "Home"
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = TabBarItem.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
