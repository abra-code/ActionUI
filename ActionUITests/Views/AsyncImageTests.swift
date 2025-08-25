// Tests/Views/AsyncImageTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class AsyncImageTests: XCTestCase {
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
            "url": "https://example.com/image.jpg",
            "placeholder": "photo.fill",
            "resizable": true,
            "contentMode": "fit"
        ]
        
        let validated = AsyncImage.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["url"] as? String, "https://example.com/image.jpg", "url should be valid String")
        XCTAssertEqual(validated["placeholder"] as? String, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(validated["resizable"] as? Bool, true, "resizable should be valid Bool")
        XCTAssertEqual(validated["contentMode"] as? String, "fit", "contentMode should be valid String")
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "url": 123,
            "placeholder": 456,
            "resizable": "true",
            "contentMode": "invalid"
        ]
        
        let validated = AsyncImage.validateProperties(properties, logger)
        
        XCTAssertNil(validated["url"], "url should be nil for invalid type")
        XCTAssertNil(validated["placeholder"], "placeholder should be nil for invalid type")
        XCTAssertNil(validated["resizable"], "resizable should be nil for invalid type")
        XCTAssertNil(validated["contentMode"], "contentMode should be nil for invalid value")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = AsyncImage.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "url": "https://example.com/image.jpg",
            "placeholder": "photo.fill"
        ]
        
        let validated = AsyncImage.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["url"] as? String, "https://example.com/image.jpg", "url should be valid String")
        XCTAssertEqual(validated["placeholder"] as? String, "photo.fill", "placeholder should be valid String")
        XCTAssertNil(validated["resizable"], "resizable should be nil when not provided")
        XCTAssertNil(validated["contentMode"], "contentMode should be nil when not provided")
    }
    
    func testValidatePropertiesInvalidUrl() throws {
        let properties: [String: Any] = [
            "url": "invalid-url",
            "placeholder": "photo.fill",
            "resizable": true,
            "contentMode": "fit"
        ]
        
        let validated = AsyncImage.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["url"] as? String, "invalid-url", "url should pass through as string, even if invalid")
        XCTAssertEqual(validated["placeholder"] as? String, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(validated["resizable"] as? Bool, true, "resizable should be valid Bool")
        XCTAssertEqual(validated["contentMode"] as? String, "fit", "contentMode should be valid String")
    }
    
    func testBuildViewAndApplyModifiersValidUrl() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "AsyncImage",
            "properties": [
                "url": "https://example.com/image.jpg",
                "placeholder": "photo.fill",
                "resizable": true,
                "contentMode": "fit"
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = AsyncImage.validateProperties(element.properties, logger)
        
        let view = AsyncImage.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = AsyncImage.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.AsyncImage<AnyView>) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers (e.g., padding), wrapping the view in _ModifiedContent
        // Note: Cannot inspect AsyncImage phase or modifiers due to SwiftUI's opaque hierarchy and async nature
    }
    
    func testBuildViewAndApplyModifiersInvalidUrl() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "AsyncImage",
            "properties": [
                "url": "invalid-url",
                "placeholder": "photo.fill",
                "resizable": true,
                "contentMode": "fit"
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = AsyncImage.validateProperties(element.properties, logger)
        
        let view = AsyncImage.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = AsyncImage.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Image) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingUrl() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "AsyncImage",
            "properties": [
                "placeholder": "photo.fill",
                "resizable": true,
                "contentMode": "fit"
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = AsyncImage.validateProperties(element.properties, logger)
        
        let view = AsyncImage.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = AsyncImage.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Image) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
