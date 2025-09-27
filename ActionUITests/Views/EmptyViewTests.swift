// Tests/Views/EmptyViewTests.swift
/*
 EmptyViewTests.swift

 Tests for the EmptyView component in the ActionUI component library.
 Minimal tests for view construction and state initialization, as most functionality is covered by ViewTests.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class EmptyViewTests: XCTestCase {
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
    
    func testEmptyViewConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "EmptyView",
            "properties": [:]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = EmptyView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        XCTAssertTrue( PropertyComparison.arePropertiesEqual(viewModel.validatedProperties, validatedProperties), "View model should include validated properties")
    }
    
    func testEmptyViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "EmptyView",
            "properties": {
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
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "EmptyView", "Element type should be EmptyView")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testEmptyViewElementCreation() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "EmptyView",
            "properties": ["padding": 10]
        ]
        
        let element = try! ActionUIElement(from: elementDict, logger: logger)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "EmptyView", "Element type should be EmptyView")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
}
