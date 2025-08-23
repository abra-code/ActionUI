// Tests/Views/CanvasTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CanvasTests: XCTestCase {
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
            "render": "fillCircle",
            "color": "#FF0000",
            "actionID": "canvas.action"
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["render"] as? String, "fillCircle", "render should be valid String")
        XCTAssertEqual(validated["color"] as? String, "#FF0000", "color should be valid String")
        XCTAssertEqual(validated["actionID"] as? String, "canvas.action", "actionID should be valid String")
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "render": 123,
            "color": 456,
            "actionID": true
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        
        XCTAssertNil(validated["render"], "render should be nil for invalid type")
        XCTAssertNil(validated["color"], "color should be nil for invalid type")
        XCTAssertNil(validated["actionID"], "actionID should be nil for invalid type")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = Canvas.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "render": "fillCircle",
            "actionID": "canvas.action"
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["render"] as? String, "fillCircle", "render should be valid String")
        XCTAssertEqual(validated["actionID"] as? String, "canvas.action", "actionID should be valid String")
        XCTAssertNil(validated["color"], "color should be nil when not provided")
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Canvas",
            "properties": [
                "render": "fillCircle",
                "color": "#FF0000",
                "actionID": "canvas.action"
            ]
        ]
        let element = try ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Canvas.validateProperties(element.properties, logger)
        
        let view = Canvas.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        let _ = Canvas.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Canvas) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers (e.g., padding), wrapping the view in _ModifiedContent
        // Note: Cannot inspect Canvas rendering or modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Canvas",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Canvas.validateProperties(element.properties, logger)
        
        let view = Canvas.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        let _ = Canvas.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Canvas) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
