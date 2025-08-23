// Tests/Views/NavigationSplitViewTests.swift
/*
 NavigationSplitViewTests.swift

 Tests for the NavigationSplitView component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for NavigationSplitView:
 {
   "type": "NavigationSplitView",
   "id": 1,
   "sidebar": {          // Note: Declared as a top-level key in JSON but stored in subviews["sidebar"] by StaticElement.init(from:).
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by StaticElement.init(from:).
     "type": "Text", "properties": { "text": "Content" }
   },
   "detail": {           // Note: Declared as a top-level key in JSON but stored in subviews["detail"] by StaticElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "columnVisibility": "all",
     "style": "balanced"
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class NavigationSplitViewTests: XCTestCase {
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
    
    func testNavigationSplitViewJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": ["type": "Text", "id": 2, "properties": ["text": "Sidebar"]],
            "content": ["type": "Text", "id": 3, "properties": ["text": "Content"]],
            "detail": ["type": "Text", "id": 4, "properties": ["text": "Detail"]],
            "properties": [
                "columnVisibility": "all",
                "style": "balanced"
            ]
        ]
        
        do {
            let element = try StaticElement(from: elementDict)
            let _ = NavigationSplitView.validateProperties(element.properties, logger)
            let sidebar = element.subviews?["sidebar"] as? any ActionUIElement
            let content = element.subviews?["content"] as? any ActionUIElement
            let detail = element.subviews?["detail"] as? any ActionUIElement
            logger.log("sidebar: \((sidebar as? StaticElement)?.type ?? "nil")", .debug)
            logger.log("content: \((content as? StaticElement)?.type ?? "nil")", .debug)
            logger.log("detail: \((detail as? StaticElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "NavigationSplitView", "Element type should be NavigationSplitView")
            XCTAssertEqual((sidebar as? StaticElement)?.type, "Text", "Sidebar should be Text")
            XCTAssertEqual((sidebar as? StaticElement)?.id, 2, "Sidebar ID should be 2")
            XCTAssertEqual((content as? StaticElement)?.type, "Text", "Content should be Text")
            XCTAssertEqual((content as? StaticElement)?.id, 3, "Content ID should be 3")
            XCTAssertEqual((detail as? StaticElement)?.type, "Text", "Detail should be Text")
            XCTAssertEqual((detail as? StaticElement)?.id, 4, "Detail ID should be 4")
            XCTAssertEqual((element.properties["columnVisibility"] as? String), "all", "Column visibility should be all")
            XCTAssertEqual((element.properties["style"] as? String), "balanced", "Style should be balanced")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
    
    func testNavigationSplitViewMalformedSidebar() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": ["id": 2, "properties": ["text": "Sidebar"]], // Missing type
            "content": ["type": "Text", "id": 3, "properties": ["text": "Content"]],
            "detail": ["type": "Text", "id": 4, "properties": ["text": "Detail"]],
            "properties": [
                "columnVisibility": "all"
            ]
        ]
        
        do {
            let element = try StaticElement(from: elementDict)
            let _ = NavigationSplitView.validateProperties(element.properties, logger)
            let sidebar = element.subviews?["sidebar"] as? any ActionUIElement
            XCTAssertNil(sidebar, "Malformed sidebar should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
