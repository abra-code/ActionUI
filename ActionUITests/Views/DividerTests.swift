// Tests/Views/DividerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DividerTests: XCTestCase {
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
            
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = Divider.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Validated properties should be empty when no properties provided")
    }
        
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Divider",
            "properties": [
                "background": "#FF0000"
            ]
        ]

        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = Divider.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = Divider.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = Divider.applyModifiers(view, element, windowUUID, validatedProperties, logger)
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
        let validatedProperties = Divider.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = Divider.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = Divider.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Divider) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
