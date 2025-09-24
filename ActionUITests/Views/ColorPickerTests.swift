// Tests/Views/ColorPickerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ColorPickerTests: XCTestCase {
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
    
    func testValidatePropertiesValid() throws {
        let properties: [String: Any] = [
            "title": "Pick a Color",
            "selectedColor": "#FF0000"
        ]
        
        let validated = ColorPicker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Pick a Color", "title should be valid String")
        XCTAssertEqual(validated["selectedColor"] as? String, "#FF0000", "selectedColor should be valid String")
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "title": 123,
            "selectedColor": true
        ]
        
        let validated = ColorPicker.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "title should be nil for invalid type")
        XCTAssertNil(validated["selectedColor"], "selectedColor should be nil for invalid type")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = ColorPicker.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "title": "Pick a Color"
        ]
        
        let validated = ColorPicker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Pick a Color", "title should be valid String")
        XCTAssertNil(validated["selectedColor"], "selectedColor should be nil when not provided")
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ColorPicker",
            "properties": [
                "title": "Pick a Color",
                "selectedColor": "#FF0000"
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = ColorPicker.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ColorPicker.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = ColorPicker.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.ColorPicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers (e.g., padding), wrapping the view in _ModifiedContent
        // Note: Cannot inspect ColorPicker state or modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ColorPicker",
            "properties": [:]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = ColorPicker.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ColorPicker.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = ColorPicker.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.ColorPicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
