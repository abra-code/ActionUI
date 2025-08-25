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
    
    func testEmptyViewConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "EmptyView",
            "properties": [:]
        ]
        let element = try! ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = EmptyView.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        XCTAssertNotNil(state.wrappedValue[element.id], "Registry should initialize state for EmptyView")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                (state.wrappedValue[element.id] as? [String: Any])?["validatedProperties"] as? [String: Any] ?? [:],
                validatedProperties
            ),
            "State should include validated properties"
        )
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
        
        let model = ActionUIModel.shared
        
        // Parse JSON into ViewElement
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
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
        
        let element = try! ViewElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "EmptyView", "Element type should be EmptyView")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
}
