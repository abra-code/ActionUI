// Tests/Views/NavigationStackTests.swift
/*
 NavigationStackTests.swift

 Tests for the NavigationStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and navigation handling.

 Sample JSON for NavigationStack:
 {
   "type": "NavigationStack",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by StaticElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "properties": {
     "navigationTitle": "App",
     "path": ["detail"]
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class NavigationStackTests: XCTestCase {
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
    
    func testNavigationStackJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationStack",
            "content": ["type": "Text", "id": 2, "properties": ["text": "Home"]],
            "properties": [
                "navigationTitle": "App",
                "path": ["detail"]
            ]
        ]
        
        do {
            let element = try StaticElement(from: elementDict)
            let _ = NavigationStack.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            logger.log("content: \((content as? StaticElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "NavigationStack", "Element type should be NavigationStack")
            XCTAssertEqual((content as? StaticElement)?.type, "Text", "Content should be Text")
            XCTAssertEqual((content as? StaticElement)?.id, 2, "Content ID should be 2")
            XCTAssertEqual((element.properties["navigationTitle"] as? String), "App", "Navigation title should be App")
            XCTAssertEqual((element.properties["path"] as? [String])?.count, 1, "Path should have 1 element")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
    
    func testNavigationStackMalformedContent() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationStack",
            "content": ["id": 2, "properties": ["text": "Home"]], // Missing type
            "properties": [
                "navigationTitle": "App"
            ]
        ]
        
        do {
            let element = try StaticElement(from: elementDict)
            let _ = NavigationStack.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
