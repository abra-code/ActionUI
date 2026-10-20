// Tests/Views/DisclosureGroupTests.swift
/*
 DisclosureGroupTests.swift

 Tests for the DisclosureGroup component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DisclosureGroupTests: XCTestCase {
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
    
    func testRegistryStateInitialization() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": ["title": "Test"]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)

        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        _ = view // Ensure view is used
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)        
    }
    
    func testPropsValid() {
        let properties: [String: Any] = [
            "title": "Details",
            "isExpanded": true
        ]
        
        let props = DisclosureGroup.Props(properties)
        
        XCTAssertEqual(props.title, "Details", "title should be valid String")
        XCTAssertEqual(props.isExpanded, true, "isExpanded should be valid Bool")
    }
    
    func testPropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "title": 123,
            "isExpanded": "true"
        ]
        
        let props = DisclosureGroup.Props(properties)
        
        XCTAssertEqual(props.title, "", "title should be ignored for invalid type")
        XCTAssertEqual(props.isExpanded, false, "isExpanded should be ignored for invalid type")
    }
    
    func testPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = DisclosureGroup.Props(properties)
        
        XCTAssertEqual(props.title, "", "title should be the default when missing")
        XCTAssertEqual(props.isExpanded, false, "isExpanded should be the default when missing")
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": [:]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)

        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        _ = DisclosureGroup.applyModifiers(view, element, windowUUID, properties, logger)
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
                "title": "Details",
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
                    "properties": ["title": "Click Me", "actionID": "buttonAction"]
                ]
            ]
        ]
        
        // Decode JSON to ActionUIElement
        let element = try! ActionUIElement(from: elementDict, logger: logger)
        
        // Verify decoded element
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "DisclosureGroup", "Element type should be DisclosureGroup")
        XCTAssertEqual(element.properties["title"] as? String, "Details", "Label should be Details")
        XCTAssertEqual(element.properties["isExpanded"] as? Bool, true, "isExpanded should be true")
        
        // Verify children are ActionUIElement instances
        let children = element.subviews?["children"] as? [any ActionUIElementBase]
        XCTAssertNotNil(children, "Children should not be nil")
        if let children {
            XCTAssertEqual(children.count, 2, "Should have 2 children")
            XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
            XCTAssertEqual((children[0] as? ActionUIElement)?.properties["text"] as? String, "Hello, World!", "First child text should be correct")
            XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Button", "Second child should be Button")
            XCTAssertEqual((children[1] as? ActionUIElement)?.properties["title"] as? String, "Click Me", "Second child title should be correct")
        }
        
        // Test corrected buildView via ActionUIRegistry
        let properties = element.properties
        
        logger.log("Creating view for element \(element.id) with children", .debug)
        let viewModel = ViewModel()
        viewModel.properties = properties
        viewModel.states = ActionUIRegistry.shared.getInitialStates(forElementType: element.type, model: viewModel)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        _ = DisclosureGroup.applyModifiers(view, element, windowUUID, properties, logger)
        logger.log("After build: state[\(element.id)] = \(String(describing: viewModel))", .debug)
        
        // Verify state initialization
        XCTAssertEqual(viewModel.states["isExpanded"] as? Bool, true, "State isExpanded should be true")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual(viewModel.properties, properties), "State properties should match")
    }
}
