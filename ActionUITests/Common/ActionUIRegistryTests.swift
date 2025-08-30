// Tests/Common/ActionUIRegistryTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIRegistryTests: XCTestCase {
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
    
    // Test that all supported views are registered during initialization
    func testViewRegistration() throws {
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
            
            let actionUIModel = ActionUIModel.shared
            let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
            guard let windowModel = actionUIModel.windowModels[windowUUID],
                  let viewModel = windowModel.viewModels[element.id] else {
                XCTFail("Failed to retrive viewModel")
                return
            }

            // expand ActionUIView.body implementation to inspect the created view before it gets wrapped with AnyView
            // let view = actionUIView.body
            let registry = ActionUIRegistry.shared
            let validatedProperties = registry.getValidatedProperties(element: element, model: viewModel)
            let view = registry.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
            
            // Allow EmptyView for specific types with empty properties
            #if canImport(AppKit)
            let tableViewType = ""
            #else
            // on non-macOS OSes Table construction does return EmptyView
            let tableViewType = "Table"
            #endif
            
            if viewType == "View" || viewType == "EmptyView" || viewType == "Link" || viewType == "ShareLink" || viewType == "VideoPlayer" || viewType == "NavigationLink" || viewType == tableViewType {
                XCTAssertTrue(view is SwiftUI.EmptyView, "buildView for '\(viewType)' should return EmptyView with empty properties")
            } else {
                XCTAssertFalse(view is SwiftUI.EmptyView, "buildView for '\(viewType)' should not return EmptyView")
            }
        }
    }
        
    // Test handling of unregistered view types
    func testUnregisteredViewType() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "UnknownView",
            "properties": ["test": "value"]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let viewModel = ViewModel(properties: element.properties)
        let registry = ActionUIRegistry.shared
        let validatedProperties = registry.getValidatedProperties(element: element, model: viewModel)
        let view = registry.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView for unregistered type should return EmptyView")
        XCTAssertTrue(PropertyComparison.arePropertiesEqual(validatedProperties, element.properties), "Unregistered view type should return original properties")
    }
    
    // Test @MainActor compliance for registration and view building
    func testMainActorCompliance() async throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [:]
        ]

        let element = try ViewElement(from: elementDict, logger: logger)
        let viewModel = ViewModel(properties: element.properties)
        
        await MainActor.run {
            let registry = ActionUIRegistry.shared
            let validatedProperties = registry.getValidatedProperties(element: element, model: viewModel)
            let view = registry.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
            XCTAssertFalse(view is SwiftUI.EmptyView, "buildView for TextField should not return EmptyView")
            XCTAssertTrue(PropertyComparison.arePropertiesEqual(validatedProperties, element.properties), "validateProperties should return input properties for valid empty input")
        }
    }    
}
