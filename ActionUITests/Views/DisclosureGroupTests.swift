// Tests/Views/DisclosureGroupTests.swift
/*
 DisclosureGroupTests.swift

 Tests for the DisclosureGroup component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DisclosureGroupTests: XCTestCase {
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
    
    func testRegistryStateInitialization() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": ["label": "Test"]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)

        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        _ = view // Ensure view is used
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)        
    }
    
    func testValidatePropertiesValid() {
        let properties: [String: Any] = [
            "label": "Details",
            "isExpanded": true
        ]
        
        let validated = DisclosureGroup.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["label"] as? String, "Details", "label should be valid String")
        XCTAssertEqual(validated["isExpanded"] as? Bool, true, "isExpanded should be valid Bool")
    }
    
    func testValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "label": 123,
            "isExpanded": "true"
        ]
        
        let validated = DisclosureGroup.validateProperties(properties, logger)
        
        XCTAssertNil(validated["label"], "label should be nil for invalid type")
        XCTAssertNil(validated["isExpanded"], "isExpanded should be nil for invalid type")
    }
    
    func testValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = DisclosureGroup.validateProperties(properties, logger)
        
        XCTAssertNil(validated["label"], "label should be nil when missing")
        XCTAssertNil(validated["isExpanded"], "isExpanded should be nil when missing")
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)

        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        _ = DisclosureGroup.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DisclosureGroup) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
        
    func testDisclosureGroupWithChildren() {
        // JSON with DisclosureGroup containing Text and Button children
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": [
                "label": "Details",
                "isExpanded": true
            ],
            "children": [
                [
                    "id": 2,
                    "type": "Text",
                    "properties": ["text": "Hello, World!"]
                ],
                [
                    "id": 3,
                    "type": "Button",
                    "properties": ["label": "Click Me", "actionID": "buttonAction"]
                ]
            ]
        ]
        
        // Decode JSON to ViewElement
        let element = try! ViewElement(from: elementDict, logger: logger)
        
        // Verify decoded element
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "DisclosureGroup", "Element type should be DisclosureGroup")
        XCTAssertEqual(element.properties["label"] as? String, "Details", "Label should be Details")
        XCTAssertEqual(element.properties["isExpanded"] as? Bool, true, "isExpanded should be true")
        
        // Verify children are ViewElement instances
        let children = element.subviews?["children"] as? [any ActionUIElement]
        XCTAssertNotNil(children, "Children should not be nil")
        if let children {
            XCTAssertEqual(children.count, 2, "Should have 2 children")
            XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
            XCTAssertEqual((children[0] as? ViewElement)?.properties["text"] as? String, "Hello, World!", "First child text should be correct")
            XCTAssertEqual((children[1] as? ViewElement)?.type, "Button", "Second child should be Button")
            XCTAssertEqual((children[1] as? ViewElement)?.properties["label"] as? String, "Click Me", "Second child label should be correct")
        }
        
        // Test corrected buildView via ActionUIRegistry
        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
        
        logger.log("Creating view for element \(element.id) with children", .debug)
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        _ = DisclosureGroup.applyModifiers(view, validatedProperties, logger)
        logger.log("After build: state[\(element.id)] = \(String(describing: viewModel))", .debug)
        
        // Verify state initialization
        XCTAssertEqual(viewModel.states["isExpanded"] as? Bool, true, "State isExpanded should be true")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual(viewModel.validatedProperties, validatedProperties), "State validatedProperties should match")
    }
}
