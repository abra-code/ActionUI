// Tests/Views/ColorPickerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ColorPickerTests: XCTestCase {
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
    
    func testColorPickerPropsValid() throws {
        let properties: [String: Any] = [
            "title": "Pick a Color",
            "selectedColor": "#FF0000"
        ]
        
        let props = ColorPicker.Props(properties)
        
        XCTAssertEqual(props.title, "Pick a Color", "title should be valid String")
        XCTAssertEqual(props.selectedColor, "#FF0000", "selectedColor should be valid String")
    }
    
    func testColorPickerPropsIgnoreInvalidValues() throws {
        let properties: [String: Any] = [
            "title": 123,
            "selectedColor": true
        ]
        
        let props = ColorPicker.Props(properties)
        
        XCTAssertEqual(props.title, "", "title should be ignored for invalid type")
        XCTAssertNil(props.selectedColor, "selectedColor should be ignored for invalid type")
    }
    
    func testColorPickerPropsMissing() throws {
        let properties: [String: Any] = [:]
        
        let props = ColorPicker.Props(properties)
        
        XCTAssertEqual(props.title, "", "title should be the default when no properties provided")
        XCTAssertNil(props.selectedColor, "selectedColor should be nil when no properties provided")
        XCTAssertNil(props.actionID, "actionID should be nil when no properties provided")
    }
    
    func testColorPickerPropsPartial() throws {
        let properties: [String: Any] = [
            "title": "Pick a Color"
        ]
        
        let props = ColorPicker.Props(properties)
        
        XCTAssertEqual(props.title, "Pick a Color", "title should be valid String")
        XCTAssertNil(props.selectedColor, "selectedColor should be nil when not provided")
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
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ColorPicker.buildView(element, viewModel, windowUUID, properties, logger)
        _ = ColorPicker.applyModifiers(view, element, windowUUID, properties, logger)
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
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ColorPicker.buildView(element, viewModel, windowUUID, properties, logger)
        _ = ColorPicker.applyModifiers(view, element, windowUUID, properties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.ColorPicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
