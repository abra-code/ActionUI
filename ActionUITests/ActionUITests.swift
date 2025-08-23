// Tests/ActionUITests.swift
/*
 ActionUITests.swift

 Integration tests for the ActionUI component library.
 Verifies the construction of an ActionUIView with a TextField element from a JSON description,
 ensuring proper state binding with ActionUIModel.shared.state and property validation.
 Uses Dictionary+Numeric extension to ensure numeric properties like padding are retrieved as Double and CGFloat.
*/

import XCTest
import SwiftUI
import CoreGraphics
@testable import ActionUI

@MainActor
final class ActionUITests: XCTestCase {
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
    
    func testActionUIViewWithTextFieldFromJSON() throws {
        // Arrange: Create JSON description for TextField with explicit floating-point padding
        let jsonString = """
        {
            "id": 1,
            "type": "TextField",
            "properties": {
                "placeholder": "Enter username",
                "textContentType": "username",
                "actionID": "text.submit",
                "padding": 8.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        
        // Parse JSON into StaticElement
        
        do {
            try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        } catch {
            XCTFail("Failed to decode JSON: \(error)")
            return
        }
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrive element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        // Verify parsed element
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "TextField", "Element type should be TextField")
        XCTAssertEqual(element.properties["placeholder"] as? String, "Enter username", "Placeholder should match")
        XCTAssertEqual(element.properties["textContentType"] as? String, "username", "textContentType should match")
        XCTAssertEqual(element.properties["actionID"] as? String, "text.submit", "actionID should match")
        XCTAssertEqual(element.properties.double(forKey: "padding"), 8.0, "Padding should be retrieved as Double with value 8.0")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 8.0, "Padding should be retrieved as CGFloat with value 8.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        // Arrange: Set up state binding
        let state = model.state(for: windowUUID)
        
        // Act: Create ActionUIView
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        
        // Act: Access the body to trigger view construction
        let view = actionUIView.body
        
        // Assert: Verify state initialization
        XCTAssertNotNil(state.wrappedValue[element.id], "State should be initialized for view ID \(element.id)")
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertNotNil(viewState, "View state should exist")
        XCTAssertEqual(viewState?["value"] as? String, "", "TextField state should initialize value to empty string")
        
        // Assert: Verify validated properties
        let validatedProperties = viewState?["validatedProperties"] as? [String: Any]
        XCTAssertNotNil(validatedProperties, "Validated properties should exist")
        XCTAssertEqual(validatedProperties?["placeholder"] as? String, "Enter username", "Validated placeholder should match")
        XCTAssertEqual(validatedProperties?["textContentType"] as? String, "username", "Validated textContentType should match")
        XCTAssertEqual(validatedProperties?["actionID"] as? String, "text.submit", "Validated actionID should match")
        XCTAssertEqual(validatedProperties?.double(forKey: "padding"), 8.0, "Validated padding should be Double with value 8.0")
        XCTAssertEqual(validatedProperties?.cgFloat(forKey: "padding"), 8.0, "Validated padding should be CGFloat with value 8.0")
        
        // Assert: Verify view construction
        XCTAssertFalse(view is SwiftUI.EmptyView, "ActionUIView body should not return EmptyView")
        XCTAssertTrue(view is AnyView, "ActionUIView body should return AnyView after applying modifiers")
        
        // Assert: Verify state binding
        model.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "testuser")
        let updatedValue = model.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "testuser", "TextField state should update value correctly")
        
        // Log state for debugging
        logger.log("Final state for viewID \(element.id): \(String(describing: viewState))", .debug)
    }
}
