// Tests/Views/ButtonTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ButtonTests: XCTestCase {
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
        let element = try ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Button.validateProperties(element.properties, logger)
        
        let view = Button.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        let _ = Button.applyModifiers(view, validatedProperties, logger)
        
        XCTAssertTrue(view is SwiftUI.Button<SwiftUI.Text>, "buildView should return Button")
        // Note: Cannot check modifiedView type as SwiftUI.Button<SwiftUI.Text> due to SwiftUI's modifier wrapping (e.g., _ModifiedContent)
        // Note: Cannot inspect buttonStyle or other modifiers due to SwiftUI's opaque view hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Button",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Button.validateProperties(element.properties, logger)
        
        let view = Button.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        let _ = Button.applyModifiers(view, validatedProperties, logger)
        
        XCTAssertTrue(view is SwiftUI.Button<SwiftUI.Text>, "buildView should return Button with default title")
        // Note: Cannot check modifiedView type as SwiftUI.Button<SwiftUI.Text> due to SwiftUI's modifier wrapping (e.g., _ModifiedContent)
        // Note: Cannot inspect buttonStyle or other modifiers due to SwiftUI's opaque view hierarchy
    }
}
