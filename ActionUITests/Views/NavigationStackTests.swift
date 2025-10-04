// Tests/Views/NavigationStackTests.swift
/*
 NavigationStackTests.swift

 Tests for the NavigationStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and navigation handling.

 Sample JSON for NavigationStack:
 {
   "type": "NavigationStack",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
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
    
    func testNavigationStackJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationStack",
            "content": {"type": "Text", "id": 2, "properties": {"text": "Home"}},
            "properties": {
                "navigationTitle": "App",
                "path": ["detail"]
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

        let validatedProperties = NavigationStack.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        let content = element.subviews?["content"] as? any ActionUIElementBase
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "NavigationStack", "Element type should be NavigationStack")
        XCTAssertEqual((content as? ActionUIElement)?.type, "Text", "Content should be Text")
        XCTAssertEqual((content as? ActionUIElement)?.id, 2, "Content ID should be 2")
        XCTAssertEqual(element.properties["navigationTitle"] as? String, "App", "Navigation title should be App")
        XCTAssertEqual((element.properties["path"] as? [String])?.count, 1, "Path should have 1 element")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
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
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
            let _ = NavigationStack.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElementBase
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
