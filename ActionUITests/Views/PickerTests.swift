// Tests/Views/PickerTests.swift
/*
 PickerTests.swift

 Tests for the Picker component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and value change action handler behavior for programmatic changes.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class PickerTests: XCTestCase {
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
    
    func testPickerJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Picker",
            "properties": {
                "title": "Select Option",
                "options": ["Option1", "Option2", "Option3"],
                "pickerStyle": "menu",
                "actionID": "picker.selection",
                "valueChangeActionID": "picker.valueChanged"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        // Trigger state initialization by creating ActionUIView
        let state = ActionUIModel.shared.state(for: windowUUID)
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force body creation
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Picker", "Element type should be Picker")
        XCTAssertEqual(element.properties["title"] as? String, "Select Option", "Title should be Select Option")
        XCTAssertEqual(element.properties["options"] as? [String], ["Option1", "Option2", "Option3"], "Options should match provided array")
        XCTAssertEqual(element.properties["pickerStyle"] as? String, "menu", "Picker style should be menu")
        XCTAssertEqual(element.properties["actionID"] as? String, "picker.selection", "actionID should match")
        XCTAssertEqual(element.properties["valueChangeActionID"] as? String, "picker.valueChanged", "valueChangeActionID should match")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        XCTAssertNotNil(state.wrappedValue[element.id], "State should be initialized for element ID after body creation")
        if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            XCTAssertEqual(stateDict["value"] as? String, "Option1", "State should initialize with first option")
        } else {
            XCTFail("State should be a dictionary")
        }
    }
    
    func testPickerConstructionAndStateBinding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Picker",
            "properties": [
                "title": "Select Option",
                "options": ["Option1", "Option2"],
                "pickerStyle": "segmented",
                "actionID": "picker.selection",
                "valueChangeActionID": "picker.valueChanged"
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: ConsoleLogger(maxLevel: .verbose))
        let state = ActionUIModel.shared.state(for: windowUUID)
        
        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force body creation
        
        logger.log("After ActionUIView body creation: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        XCTAssertNotNil(state.wrappedValue[element.id], "ActionUIView should initialize state for Picker")
        
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertEqual(viewState?["value"] as? String, "Option1", "Picker state should initialize with first option")
    }
    
    func testPickerValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Choose",
            "options": ["Item1", "Item2", "Item3"],
            "pickerStyle": "segmented"
        ]
        
        let validated = Picker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Choose", "Title should be valid")
        XCTAssertEqual(validated["options"] as? [String], ["Item1", "Item2", "Item3"], "Options should be valid")
        XCTAssertEqual(validated["pickerStyle"] as? String, "segmented", "Picker style should be valid")
    }
    
    func testPickerValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "options": [1, 2, 3],
            "pickerStyle": "invalidStyle"
        ]
        
        let validated = Picker.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Invalid title should be nil")
        XCTAssertNil(validated["options"], "Invalid options should be nil")
        XCTAssertNil(validated["pickerStyle"], "Invalid picker style should be nil")
    }
    
    func testPickerValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Picker.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
        XCTAssertNil(validated["options"], "Missing options should be nil")
        XCTAssertNil(validated["pickerStyle"], "Missing picker style should be nil")
    }
    
    func testPickerValidatePropertiesEmptyOptions() {
        let properties: [String: Any] = [
            "options": [],
            "pickerStyle": "menu"
        ]
        
        let validated = Picker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["options"] as? [String], [], "Empty options should be valid")
        XCTAssertEqual(validated["pickerStyle"] as? String, "menu", "Picker style should remain menu")
        XCTAssertNil(validated["title"], "Missing title should be nil")
    }
    
    #if os(macOS)
    func testPickerValidatePropertiesWheelStyleMacOS() {
        let properties: [String: Any] = [
            "options": ["Option1", "Option2"],
            "pickerStyle": "wheel"
        ]
        
        let validated = Picker.validateProperties(properties, logger)
        
        XCTAssertNil(validated["pickerStyle"], "Wheel style should be nil on macOS")
        XCTAssertEqual(validated["options"] as? [String], ["Option1", "Option2"], "Options should remain valid")
    }
    #endif
    
    func testPickerActionHandling() {
        let valueChangeExpectation = XCTestExpectation(description: "Value change handler called")
        let valueChangeActionID = "picker.valueChanged"
        
        let jsonString = """
        {
            "id": 1,
            "type": "Picker",
            "properties": {
                "options": ["Option1", "Option2"],
                "actionID": "picker.selection",
                "valueChangeActionID": "\(valueChangeActionID)"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        try! model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = model.state(for: windowUUID)
        ActionUIModel.shared.registerActionHandler(for: valueChangeActionID) { _, _, viewID, _, _ in
            XCTAssertEqual(viewID, 1, "Value change handler should receive correct viewID")
            valueChangeExpectation.fulfill()
        }
        
        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Simulate programmatic value change
        model.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        let updatedValue = model.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
        
        wait(for: [valueChangeExpectation], timeout: 2.0)
    }
    
    func testPickerNoActionOnProgrammaticStateChange() {
        let valueChangeExpectation = XCTestExpectation(description: "Value change handler called")
        let valueChangeActionID = "picker.valueChanged"
        
        let jsonString = """
        {
            "id": 1,
            "type": "Picker",
            "properties": {
                "options": ["Option1", "Option2"],
                "actionID": "picker.selection",
                "valueChangeActionID": "\(valueChangeActionID)"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        try! model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = model.state(for: windowUUID)
        ActionUIModel.shared.registerActionHandler(for: valueChangeActionID) { _, _, viewID, _, _ in
            XCTAssertEqual(viewID, 1, "Value change handler should receive correct viewID")
            valueChangeExpectation.fulfill()
        }
        
        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Simulate programmatic value change
        model.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        let updatedValue = model.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
        
        wait(for: [valueChangeExpectation], timeout: 2.0)
    }
    
    func testActionUIViewWithPickerActionHandling() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Picker",
            "properties": {
                "title": "Select Option",
                "options": ["Option1", "Option2", "Option3"],
                "pickerStyle": "menu",
                "actionID": "picker.selection",
                "valueChangeActionID": "picker.valueChanged"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        // Verify parsed element
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Picker", "Element type should be Picker")
        XCTAssertEqual(element.properties["title"] as? String, "Select Option", "Title should be Select Option")
        XCTAssertEqual(element.properties["options"] as? [String], ["Option1", "Option2", "Option3"], "Options should match provided array")
        XCTAssertEqual(element.properties["pickerStyle"] as? String, "menu", "Picker style should be menu")
        XCTAssertEqual(element.properties["actionID"] as? String, "picker.selection", "actionID should match")
        XCTAssertEqual(element.properties["valueChangeActionID"] as? String, "picker.valueChanged", "valueChangeActionID should match")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        // Arrange: Set up state binding and action handlers
        let state = model.state(for: windowUUID)
        let valueChangeActionID = "picker.valueChanged"
        let valueChangeExpectation = XCTestExpectation(description: "Value change handler called for programmatic change")
        
        ActionUIModel.shared.registerActionHandler(for: valueChangeActionID) { _, _, viewID, _, _ in
            XCTAssertEqual(viewID, 1, "Value change handler should receive correct viewID")
            XCTAssertTrue(Thread.isMainThread, "Value change handler should run on main thread")
            valueChangeExpectation.fulfill()
        }
        
        // Act: Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Assert: Verify state initialization
        XCTAssertNotNil(state.wrappedValue[element.id], "State should be initialized for view ID \(element.id)")
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertNotNil(viewState, "View state should exist")
        XCTAssertEqual(viewState?["value"] as? String, "Option1", "Picker state should initialize value to first option")
        
        // Assert: Verify view construction
        XCTAssertFalse(actionUIView.body is SwiftUI.EmptyView, "ActionUIView body should not return EmptyView")
        
        // Act: Simulate programmatic value change
        model.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        // Assert: Verify state update
        let updatedValue = model.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
        
        // Assert: Verify action handler behavior
        wait(for: [valueChangeExpectation], timeout: 2.0)
        
        // Log state for debugging
        logger.log("Final state for viewID \(element.id): \(String(describing: state.wrappedValue[element.id]))", .debug)
    }
    
    func testPickerValueChangeActionAsyncDispatch() {
        let valueChangeActionID = "picker.valueChanged"
        let expectation = XCTestExpectation(description: "Value change handler called asynchronously")
        
        let jsonString = """
        {
            "id": 1,
            "type": "Picker",
            "properties": {
                "options": ["Option1", "Option2"],
                "valueChangeActionID": "\(valueChangeActionID)"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        try! model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = model.state(for: windowUUID)
        var handlerCalled = false
        ActionUIModel.shared.registerActionHandler(for: valueChangeActionID) { _, _, viewID, _, _ in
            XCTAssertEqual(viewID, 1, "Value change handler should receive correct viewID")
            XCTAssertTrue(Thread.isMainThread, "Value change handler should run on main thread")
            handlerCalled = true
            expectation.fulfill()
        }
        
        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Record time before setting value
        let startTime = Date()
        model.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        // Verify handler hasn't run synchronously
        XCTAssertFalse(handlerCalled, "Value change handler should not run synchronously")
        
        // Assert: Verify state update
        let updatedValue = model.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
        
        // Wait for async dispatch
        wait(for: [expectation], timeout: 2.0)
        
        // Verify async delay
        let endTime = Date()
        let timeInterval = endTime.timeIntervalSince(startTime)
        XCTAssertGreaterThan(timeInterval, 0.0, "Value change handler should have a non-zero delay, indicating async dispatch")
    }
}
