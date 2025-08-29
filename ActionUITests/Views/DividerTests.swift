// Tests/Views/DividerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DividerTests: XCTestCase {
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
            "background": "#FF0000",
            "frameHeight": 2.0,
            "frameWidth": 3.0
        ]
        
        let validated = Divider.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["background"] as? String, "#FF0000", "background should be valid String")
        XCTAssertEqual(validated.double(forKey: "frameHeight"), 2.0, "frameHeight should be valid Double")
        XCTAssertEqual(validated.double(forKey: "frameWidth"), 3.0, "frameWidth should be valid Double")
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "background": 123,
            "frameHeight": -1.0,
            "frameWidth": "3.0"
        ]
        
        let validated = Divider.validateProperties(properties, logger)
        
        XCTAssertNil(validated["background"], "background should be nil for invalid type")
        XCTAssertNil(validated["frameHeight"], "frameHeight should be nil for negative value")
        XCTAssertNil(validated["frameWidth"], "frameWidth should be nil for invalid type")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = Divider.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "background": "#FF0000"
        ]
        
        let validated = Divider.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["background"] as? String, "#FF0000", "background should be valid String")
        XCTAssertNil(validated["frameHeight"], "frameHeight should be nil when not provided")
        XCTAssertNil(validated["frameWidth"], "frameWidth should be nil when not provided")
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Divider",
            "properties": [
                "background": "#FF0000",
                "frameHeight": 2.0,
                "frameWidth": 3.0
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Divider.validateProperties(element.properties, logger)
        
        let view = Divider.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = Divider.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Divider) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect Divider modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Divider",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Divider.validateProperties(element.properties, logger)
        
        let view = Divider.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = Divider.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Divider) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
