// Tests/Views/ColorPickerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ColorPickerTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
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
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ColorPicker.validateProperties(element.properties, logger)
        
        let view = ColorPicker.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = ColorPicker.applyModifiers(view, validatedProperties, logger)
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
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ColorPicker.validateProperties(element.properties, logger)
        
        let view = ColorPicker.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = ColorPicker.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.ColorPicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testColorPickerStateBinding() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ColorPicker",
            "properties": [
                "title": "Pick a Color",
                "selectedColor": "#FF0000"
            ]
        ]
        
        let windowUUID = UUID().uuidString
        let model = ActionUIModel.shared
        try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = model.state(for: windowUUID)

        // Create ActionUIView and force body creation
        let actionUIView = ActionUIView(element: element, state: state, windowUUID: windowUUID)
        _ = actionUIView.body // Force body creation

        // Verify state initialization
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertNotNil(viewState, "State should be initialized for ColorPicker")
        XCTAssertNotNil(viewState?["value"] as? Color, "ColorPicker state should include a Color value")
        XCTAssertNotNil(viewState?["validatedProperties"] as? [String: Any], "State should include validated properties")
    }
}
