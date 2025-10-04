// Tests/Views/TabBarItemTests.swift
/*
 TabBarItemTests.swift

 Tests for the TabBarItem component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for TabBarItem:
 {
   "type": "TabBarItem",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
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
    
    func testTabBarItemJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TabBarItem",
            "content": {"type": "Text", "id": 2, "properties": {"text": "Home"}},
            "properties": {
                "title": "Home",
                "systemImage": "house"
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

        let validatedProperties = TabBarItem.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        let content = element.subviews?["content"] as? any ActionUIElementBase
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "TabBarItem", "Element type should be TabBarItem")
        XCTAssertEqual((content as? ActionUIElement)?.type, "Text", "Content should be Text")
        XCTAssertEqual((content as? ActionUIElement)?.id, 2, "Content ID should be 2")
        XCTAssertEqual(element.properties["title"] as? String, "Home", "Title should be Home")
        XCTAssertEqual(element.properties["systemImage"] as? String, "house", "SystemImage should be house")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
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
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
            let _ = TabBarItem.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElementBase
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
