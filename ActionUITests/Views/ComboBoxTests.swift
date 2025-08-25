// Tests/Views/ComboBoxTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ComboBoxTests: XCTestCase {
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
        #if os(macOS) || os(iOS)
        let properties: [String: Any] = [
            "placeholder": "Select an option",
            "options": ["Option1", "Option2"]
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Select an option", "placeholder should be valid String")
        XCTAssertEqual(validated["options"] as? [String], ["Option1", "Option2"], "options should be valid [String]")
        #else
        let properties: [String: Any] = [
            "placeholder": "Select an option",
            "options": ["Option1", "Option2"]
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Properties should be empty on watchOS/tvOS")
        #endif
    }
    
    func testValidatePropertiesInvalid() throws {
        #if os(macOS) || os(iOS)
        let properties: [String: Any] = [
            "placeholder": 123,
            "options": [1, 2]
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "placeholder should be nil for invalid type")
        XCTAssertNil(validated["options"], "options should be nil for invalid type")
        #else
        let properties: [String: Any] = [
            "placeholder": 123,
            "options": [1, 2]
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Properties should be empty on watchOS/tvOS")
        #endif
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        #if os(macOS) || os(iOS)
        XCTAssertTrue(validated.isEmpty, "Validated properties should be empty when no properties provided")
        #else
        XCTAssertTrue(validated.isEmpty, "Properties should be empty on watchOS/tvOS")
        #endif
    }
    
    func testValidatePropertiesPartial() throws {
        #if os(macOS) || os(iOS)
        let properties: [String: Any] = [
            "placeholder": "Select an option"
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Select an option", "placeholder should be valid String")
        XCTAssertNil(validated["options"], "options should be nil when not provided")
        #else
        let properties: [String: Any] = [
            "placeholder": "Select an option"
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Properties should be empty on watchOS/tvOS")
        #endif
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        #if os(macOS) || os(iOS)
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [
                "placeholder": "Select an option",
                "options": ["Option1", "Option2"]
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        
        let view = ComboBox.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = ComboBox.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.HStack) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers (e.g., padding), wrapping the view in _ModifiedContent
        // Note: Cannot inspect ComboBox components or modifiers due to SwiftUI's opaque hierarchy
        #else
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [
                "placeholder": "Select an option",
                "options": ["Option1", "Option2"]
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        
        let view = ComboBox.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        XCTAssertTrue(view is SwiftUI.EmptyView, "ComboBox should return EmptyView on watchOS/tvOS")
        #endif
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        #if os(macOS) || os(iOS)
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        
        let view = ComboBox.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = ComboBox.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.HStack) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
        #else
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        
        let view = ComboBox.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        XCTAssertTrue(view is SwiftUI.EmptyView, "ComboBox should return EmptyView on watchOS/tvOS")
        #endif
    }
    
    func testComboBoxStateBinding() throws {
        #if os(macOS) || os(iOS)
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [
                "placeholder": "Select an option",
                "options": ["Option1", "Option2"]
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        
        let _ = ComboBox.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        
        // Verify state initialization
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertNotNil(viewState, "State should be initialized for ComboBox")
        XCTAssertEqual(viewState?["value"] as? String, "", "ComboBox state should include an empty String value")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                viewState?["validatedProperties"] as? [String: Any] ?? [:],
                validatedProperties
            ),
            "State should include validated properties"
        )
        #endif
    }
}
