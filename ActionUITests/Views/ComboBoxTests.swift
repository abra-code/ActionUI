// Tests/Views/ComboBoxTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ComboBoxTests: XCTestCase {
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
            "placeholder": "Select an option",
            "options": ["Option1", "Option2"]
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        #if os(macOS) || os(iOS)
        XCTAssertEqual(validated["placeholder"] as? String, "Select an option", "placeholder should be valid String")
        XCTAssertEqual(validated["options"] as? [String], ["Option1", "Option2"], "options should be valid [String]")
        #else
        XCTAssertTrue(validated.isEmpty, "Properties should be empty on watchOS/tvOS")
        #endif
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "placeholder": 123,
            "options": [1, 2]
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        #if os(macOS) || os(iOS)
        XCTAssertNil(validated["placeholder"], "placeholder should be nil for invalid type")
        XCTAssertNil(validated["options"], "options should be nil for invalid type")
        #else
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
        let properties: [String: Any] = [
            "placeholder": "Select an option"
        ]
        
        let validated = ComboBox.validateProperties(properties, logger)
        
        #if os(macOS) || os(iOS)
        XCTAssertEqual(validated["placeholder"] as? String, "Select an option", "placeholder should be valid String")
        XCTAssertNil(validated["options"], "options should be nil when not provided")
        #else
        XCTAssertTrue(validated.isEmpty, "Properties should be empty on watchOS/tvOS")
        #endif
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [
                "placeholder": "Select an option",
                "options": ["Option1", "Option2"]
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        #if os(macOS) || os(iOS)
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let view = actionUIView.body // Access the body to trigger view construction

        // Note: Avoid strict type checks (e.g., SwiftUI.HStack) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers (e.g., padding), wrapping the view in _ModifiedContent
        // Note: Cannot inspect ComboBox components or modifiers due to SwiftUI's opaque hierarchy
        #else
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        let view = ComboBox.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        XCTAssertTrue(view is SwiftUI.EmptyView, "ComboBox should return EmptyView on watchOS/tvOS")
        #endif
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ComboBox",
            "properties": [:]
        ]

        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = ComboBox.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ComboBox.buildView(element, viewModel, windowUUID, validatedProperties, logger)

        #if os(macOS) || os(iOS)
        _ = ComboBox.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.HStack) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
        #else
        XCTAssertTrue(view is SwiftUI.EmptyView, "ComboBox should return EmptyView on watchOS/tvOS")
        #endif
    }    
}
