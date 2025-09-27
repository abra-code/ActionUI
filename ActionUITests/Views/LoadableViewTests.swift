// Tests/Views/LoadableViewTests.swift
/*
 LoadableViewTests.swift

 Tests for the LoadableView component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LoadableViewTests: XCTestCase {
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
    
    func testLoadableViewValidatePropertiesValid() {
        let properties: [String: Any] = [
            "url": "https://example.com/view.json"
        ]
        
        let validated = LoadableView.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["url"] as? String, "https://example.com/view.json", "url should be valid")
    }
    
    func testLoadableViewValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "url": 123
        ]
        
        let consoleLogger = ConsoleLogger()
        let validated = LoadableView.validateProperties(properties, consoleLogger)
        
        XCTAssertNil(validated["url"], "Invalid url should be nil")
    }
    
    func testLoadableViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "LoadableView",
            "properties": {
                "url": "https://example.com/view.json",
                "padding": 10.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        // Verify element properties
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "LoadableView", "Element type should be LoadableView")
        XCTAssertEqual(element.properties["url"] as? String, "https://example.com/view.json", "url should be https://example.com/view.json")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        
        // Verify ViewModel setup
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? String, "https://example.com/view.json", "Initial viewModel value should be the URL string")
        
//        // Verify view construction
//        let validatedProperties = LoadableView.validateProperties(element.properties, logger)
//        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
//        XCTAssertTrue(view is SwiftUI.AnyView, "Built view should be wrapped in AnyView")
    }
}
