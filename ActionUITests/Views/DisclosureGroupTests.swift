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
    
    func testRegistryStateInitialization() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": ["label": "Test"]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
                
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        _ = view // Ensure view is used
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        XCTAssertNotNil(state.wrappedValue[element.id], "Registry should initialize state")
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
    
    func testBuildViewAndApplyModifiersMissingProperties() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": [:]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        _ = DisclosureGroup.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DisclosureGroup) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testDisclosureGroupStateBinding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DisclosureGroup",
            "properties": [
                "label": "Details",
                "isExpanded": true
            ],
            "children": [
                ["id": 2, "type": "Text", "properties": ["text": "Content"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
        
        logger.log("Creating view for element \(element.id)", .debug)
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        _ = view // Ensure view is used
        logger.log("After build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        // Verify state initialization
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        logger.log("State for element \(element.id): \(String(describing: viewState))", .debug)
        XCTAssertNotNil(viewState, "State should be initialized for DisclosureGroup")
        XCTAssertEqual(viewState?["isExpanded"] as? Bool, true, "DisclosureGroup state should include isExpanded value")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                viewState?["validatedProperties"] as? [String: Any] ?? [:],
                validatedProperties
            ),
            "State should include validated properties"
        )
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
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DisclosureGroup.validateProperties(element.properties, logger)
        
        logger.log("Creating view for element \(element.id) with children", .debug)
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        _ = DisclosureGroup.applyModifiers(view, validatedProperties, logger)
        logger.log("After build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        // Verify state initialization
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        logger.log("State for element \(element.id): \(String(describing: viewState))", .debug)
        XCTAssertNotNil(viewState, "State should be initialized for DisclosureGroup")
        XCTAssertEqual(viewState?["isExpanded"] as? Bool, true, "State isExpanded should be true")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual(viewState?["validatedProperties"] as? [String: Any] ?? [:], validatedProperties), "State validatedProperties should match")
        
        // Test buggy buildView (using properties["children"])
        let buggyBuildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
            let label = properties["label"] as? String ?? ""
            let initialExpanded = properties["isExpanded"] as? Bool ?? false
            let viewState = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
                ["isExpanded": initialExpanded, "validatedProperties": properties],
                uniquingKeysWith: { _, new in new }
            )
            state.wrappedValue[element.id] = viewState
            let expandedBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["isExpanded"] as? Bool ?? initialExpanded },
                set: { newValue in
                    let updatedState = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
                        ["isExpanded": newValue, "validatedProperties": properties],
                        uniquingKeysWith: { _, new in new }
                    )
                    state.wrappedValue[element.id] = updatedState
                    if let actionID = properties["actionID"] as? String {
                        Task { @MainActor in
                            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                        }
                    }
                }
            )
            let children = properties["children"] as? [[String: Any]] ?? []
            return SwiftUI.DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(children.indices, id: \.self) { index in
                    guard let childElement = try? ViewElement(from: children[index], logger: logger) else {
                        logger.log("Failed to create ViewElement from child at index \(index)", .error)
                        return ActionUIView(element: ViewElement(id: -1, type: "EmptyView", properties: [:], subviews: nil), state: state, windowUUID: windowUUID)
                    }
                    return ActionUIView(element: childElement, state: state, windowUUID: windowUUID)
                }
            } label: {
                SwiftUI.Text(label)
            }
        }
        
        let buggyView = buggyBuildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = DisclosureGroup.applyModifiers(buggyView, validatedProperties, logger)
        // Note: Buggy buildView uses properties["children"], which is nil, so no children are rendered
    }
}
