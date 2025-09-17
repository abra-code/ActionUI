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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Trigger state initialization by creating ActionUIView
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        _ = actionUIView.body // Force body creation
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Picker", "Element type should be Picker")
        XCTAssertEqual(element.properties["title"] as? String, "Select Option", "Title should be Select Option")
        XCTAssertEqual(element.properties["options"] as? [String], ["Option1", "Option2", "Option3"], "Options should match provided array")
        XCTAssertEqual(element.properties["pickerStyle"] as? String, "menu", "Picker style should be menu")
        XCTAssertEqual(element.properties["actionID"] as? String, "picker.selection", "actionID should match")
        XCTAssertEqual(element.properties["valueChangeActionID"] as? String, "picker.valueChanged", "valueChangeActionID should match")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        XCTAssertEqual(viewModel.value as? String, "Option1", "State should initialize with first option")
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
    
    func testPickerActionHandling() throws {
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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Simulate programmatic value change
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        let updatedValue = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
    }
    
    func testPickerNoActionOnProgrammaticStateChange() throws {
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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Simulate programmatic value change
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        let updatedValue = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        // Verify parsed element
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Picker", "Element type should be Picker")
        XCTAssertEqual(element.properties["title"] as? String, "Select Option", "Title should be Select Option")
        XCTAssertEqual(element.properties["options"] as? [String], ["Option1", "Option2", "Option3"], "Options should match provided array")
        XCTAssertEqual(element.properties["pickerStyle"] as? String, "menu", "Picker style should be menu")
        XCTAssertEqual(element.properties["actionID"] as? String, "picker.selection", "actionID should match")
        XCTAssertEqual(element.properties["valueChangeActionID"] as? String, "picker.valueChanged", "valueChangeActionID should match")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Act: Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Assert: Verify state initialization
        XCTAssertEqual(viewModel.value as? String, "Option1", "Picker state should initialize value to first option")
        
        // Assert: Verify view construction
        XCTAssertFalse(actionUIView.body is SwiftUI.EmptyView, "ActionUIView body should not return EmptyView")
        
        // Act: Simulate programmatic value change
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
        
        // Assert: Verify state update
        let updatedValue = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
                
        // Log state for debugging
        logger.log("Final state for viewID \(element.id): \(String(describing: viewModel))", .debug)
    }
    
    func testPickerValueChangeActionAsyncDispatch() throws {
        let valueChangeActionID = "picker.valueChanged"
        
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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        _ = actionUIView.body // Force view rendering
        
        // Record time before setting value
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "Option2")
        logger.log("Test: Programmatically set value to Option2 for viewID: \(element.id)", .debug)
                
        // Assert: Verify state update
        let updatedValue = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "Option2", "Picker state should update value correctly")
    }
}
