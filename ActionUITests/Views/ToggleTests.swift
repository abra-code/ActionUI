// Tests/Views/ToggleTests.swift
/*
 ToggleTests.swift

 Tests for the Toggle component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, state binding, and platform-specific style application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToggleTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testTogglePropsValid() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "switch",
            "actionID": "toggle.submit"
        ]
        
        let props = Toggle.Props(properties)
        
        XCTAssertEqual(props.title, "Enable Feature", "Title should be valid")
        XCTAssertEqual(props.style, .switch, "Style should be valid")
        XCTAssertEqual(props.actionID, "toggle.submit", "actionID should be valid")
    }
    
    func testTogglePropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "title": 123,
            "style": "invalidStyle"
        ]
        
        let props = Toggle.Props(properties)
        
        XCTAssertEqual(props.title, "Toggle", "Invalid title should be the default")
        XCTAssertNil(props.style, "Invalid style should be nil")
    }
    
    func testTogglePropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Toggle.Props(properties)
        
        XCTAssertEqual(props.title, "Toggle", "Missing title should be the default")
        XCTAssertNil(props.style, "Missing style should be nil")
        XCTAssertNil(props.actionID, "Missing actionID should be nil")
    }
    
    #if os(macOS)
    func testTogglePropsMacOSCheckbox() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "checkbox"
        ]
        
        let props = Toggle.Props(properties)
        
        XCTAssertEqual(props.style, .checkbox, "Checkbox style should be valid on macOS")
    }
    #else
    func testTogglePropsNonMacOSCheckbox() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "checkbox"
        ]
        
        let props = Toggle.Props(properties)
        
        // Read on every platform; the renderer applies no style for it off macOS.
        XCTAssertEqual(props.style, .checkbox, "checkbox is read on every platform")
    }
    #endif
    
    func testToggleConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Toggle",
            "properties": [
                "title": "Enable Feature",
                "style": "switch",
                "actionID": "toggle.submit",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testToggleJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Toggle",
            "properties": {
                "title": "Enable Feature",
                "style": "switch",
                "actionID": "toggle.submit",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
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
        XCTAssertEqual(element.type, "Toggle", "Element type should be Toggle")
        XCTAssertEqual(element.properties["title"] as? String, "Enable Feature", "title should be Enable Feature")
        XCTAssertEqual(element.properties["style"] as? String, "switch", "style should be switch")
        XCTAssertEqual(element.properties["actionID"] as? String, "toggle.submit", "actionID should be toggle.submit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? Bool, false, "Initial viewModel value should be false")
    }

    func testTogglePropsIsOn() {
        let valid = Toggle.Props(["isOn": true])
        XCTAssertEqual(valid.isOn, true, "Valid isOn should be preserved")

        let invalid = Toggle.Props(["isOn": "yes"])
        XCTAssertNil(invalid.isOn, "Non-Bool isOn should be ignored")
    }

    func testToggleInitialValueFromIsOnProperty() {
        let viewModel = ViewModel()
        viewModel.properties = ["isOn": true]

        let value = Toggle.initialValue(viewModel) as? Bool
        XCTAssertEqual(value, true, "initialValue should fall back to isOn property")
    }

    func testToggleInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = false
        viewModel.properties = ["isOn": true]

        let value = Toggle.initialValue(viewModel) as? Bool
        XCTAssertEqual(value, false, "initialValue should prefer model.value over isOn property")
    }
}
