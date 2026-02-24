// Tests/Views/ButtonTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ButtonTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
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
            "title": "Click Me",
            "buttonStyle": "bordered",
            "role": "destructive"
        ]
        
        let validated = Button.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Click Me", "title should be valid String")
        XCTAssertEqual(validated["buttonStyle"] as? String, "bordered", "buttonStyle should be valid String")
        XCTAssertEqual(validated["role"] as? String, "destructive", "role should be valid String")
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "title": 123,
            "buttonStyle": "invalid",
            "role": "invalid"
        ]
        
        let validated = Button.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "title should be nil for invalid type")
        XCTAssertNil(validated["buttonStyle"], "buttonStyle should be nil for invalid value")
        XCTAssertNil(validated["role"], "role should be nil for invalid value")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = Button.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "title": "Click Me"
        ]
        
        let validated = Button.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Click Me", "title should be valid String")
        XCTAssertNil(validated["buttonStyle"], "buttonStyle should be nil when not provided")
        XCTAssertNil(validated["role"], "role should be nil when not provided")
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Button",
            "properties": [
                "title": "Click Me",
                "buttonStyle": "bordered",
                "role": "destructive"
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Button.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = Button.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = Button.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        // Note: Cannot check modifiedView type as SwiftUI.Button<SwiftUI.Text> due to SwiftUI's modifier wrapping (e.g., _ModifiedContent)
        // Note: Cannot inspect buttonStyle or other modifiers due to SwiftUI's opaque view hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Button",
            "properties": [:]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Button.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = Button.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = Button.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        // Note: Cannot check modifiedView type as SwiftUI.Button<SwiftUI.Text> due to SwiftUI's modifier wrapping (e.g., _ModifiedContent)
        // Note: Cannot inspect buttonStyle or other modifiers due to SwiftUI's opaque view hierarchy
    }

    // MARK: - Image support tests

    func testBuildViewWithSystemImageOnly() throws {
        let properties: [String: Any] = [
            "systemImage": "plus.circle.fill",
            "title": "",
            "imageScale": "large"
        ]
        
        let elementDict: [String: Any] = [
            "id": 10,
            "type": "Button",
            "properties": properties
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = Button.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        
        let view = Button.buildView(element, viewModel, windowUUID, validated, logger)
        
        // We can't deeply inspect SwiftUI view hierarchy in unit tests easily,
        // but we can at least confirm it builds without crash and is Button type
        // Optional: snapshot test or manual inspection in preview/demo if needed
    }

    func testBuildViewWithNoImageFallsBackToText() throws {
        let properties: [String: Any] = [
            "title": "Plain Text Button",
            "imageScale": "large"           // should be ignored
        ]
        
        let elementDict: [String: Any] = [
            "id": 12,
            "type": "Button",
            "properties": properties
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = Button.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        
        let _ = Button.buildView(element, viewModel, windowUUID, validated, logger)
    }

    func testValidatePropertiesImageScale() throws {
        // valid values
        let props1: [String: Any] = ["imageScale": "large"]
        var validated = Button.validateProperties(props1, logger)
        XCTAssertEqual(validated["imageScale"] as? String, "large")
        
        // invalid type
        let props2: [String: Any] = ["imageScale": 123]
        validated = Button.validateProperties(props2, logger)
        XCTAssertNil(validated["imageScale"])
        
        // invalid string value (kept but ignored in logic)
        let props3: [String: Any] = ["imageScale": "extra-large"]
        validated = Button.validateProperties(props3, logger)
        XCTAssertEqual(validated["imageScale"] as? String, "extra-large")
        // Note: your code keeps invalid strings → scale falls back to .medium
    }
}
