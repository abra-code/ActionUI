// Tests/Common/ActionUIRegistryTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIRegistryTests: XCTestCase {
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
    
    // Test that all supported views are registered during initialization
    func testViewRegistration() throws {
        let registry = ActionUIRegistry.shared
        let expectedViewTypes = [
            "AsyncImage", "Button", "Canvas", "ColorPicker", "ComboBox", "DatePicker",
            "DisclosureGroup", "Divider", "EmptyView", "Form", "Gauge", "Grid", "Group",
            "HStack", "Image", "KeyframeAnimator", "Label", "LazyHGrid", "LazyHStack",
            "LazyVGrid", "LazyVStack", "Link", "List", "Map", "Menu", "NavigationLink",
            "NavigationStack", "NavigationSplitView", "PhaseAnimator", "Picker",
            "ProgressView", "ScrollView", "ScrollViewReader", "Section", "SecureField",
            "ShareLink", "Slider", "Spacer", "TabBarItem", "Table", "Text", "TextEditor",
            "TextField", "Toggle", "VStack", "VideoPlayer", "View", "ZStack", "TabView"
        ]
        
        for viewType in expectedViewTypes {
            let elementDict: [String: Any] = [
                "id": 1,
                "type": viewType,
                "properties": [:]
            ]
            let element = try ViewElement(from: elementDict, logger: logger)
            let state = ActionUIModel.shared.state(for: UUID().uuidString)
            let validatedProperties = registry.getValidatedProperties(element: element, state: state)
            
            let view = registry.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
            
            // Allow EmptyView for specific types with empty properties
            if viewType == "View" || viewType == "EmptyView" || viewType == "Link" || viewType == "ShareLink" || viewType == "VideoPlayer" || viewType == "NavigationLink" {
                XCTAssertTrue(view is SwiftUI.EmptyView, "buildView for '\(viewType)' should return EmptyView with empty properties")
            } else {
                XCTAssertFalse(view is SwiftUI.EmptyView, "buildView for '\(viewType)' should not return EmptyView")
            }
        }
    }
    
    // Test manual registration of a new view type
    func testManualViewRegistration() throws {
        let registry = ActionUIRegistry.shared
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        
        struct MockView: ActionUIViewConstruction {
            static var valueType: Any.Type { String.self }
            static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, _ in properties }
            static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in Text("Mock") }
            static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _ in view }
        }
        
        registry.register(MockView.self)
        
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "MockView",
            "properties": ["test": "value"]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = registry.getValidatedProperties(element: element, state: state)
        let view = registry.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        XCTAssertFalse(view is SwiftUI.EmptyView, "buildView for 'MockView' should return a valid view")
        XCTAssertTrue(view is SwiftUI.Text, "buildView for 'MockView' should return a Text view")
    }
    
    // Test handling of unregistered view types
    func testUnregisteredViewType() throws {
        let registry = ActionUIRegistry.shared
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "UnknownView",
            "properties": ["test": "value"]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        
        let validatedProperties = registry.getValidatedProperties(element: element, state: state)
        let view = registry.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView for unregistered type should return EmptyView")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual(validatedProperties, element.properties), "Unregistered view type should return original properties")
    }
    
    // Test @MainActor compliance for registration and view building
    func testMainActorCompliance() async throws {
        let registry = ActionUIRegistry.shared
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [:]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        
        await MainActor.run {
            let validatedProperties = registry.getValidatedProperties(element: element, state: state)
            let view = registry.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
            XCTAssertFalse(view is SwiftUI.EmptyView, "buildView for TextField should not return EmptyView")
            XCTAssertTrue(PropertyComparison.arePropertiesEqual(validatedProperties, element.properties), "validateProperties should return input properties for valid empty input")
        }
    }
    
    // Test state initialization in buildView
    func testStateInitialization() throws {
        let registry = ActionUIRegistry.shared
        let windowUUID = UUID().uuidString
        let state = ActionUIModel.shared.state(for: windowUUID)
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": ["placeholder": "Enter text"]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        
        let validatedProperties = registry.getValidatedProperties(element: element, state: state)
        _ = registry.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        XCTAssertNotNil(state.wrappedValue[1], "State should be initialized for view ID 1")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual((state.wrappedValue[1] as? [String: Any])?["validatedProperties"] as? [String: Any] ?? [:], validatedProperties), "Validated properties should match")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual((state.wrappedValue[1] as? [String: Any])?["rawProperties"] as? [String: Any] ?? [:], element.properties), "Raw properties should match element properties")
    }
}
