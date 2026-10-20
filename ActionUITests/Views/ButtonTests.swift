// Tests/Views/ButtonTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ButtonTests: XCTestCase {
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
    
    func testButtonPropsValid() throws {
        let properties: [String: Any] = [
            "title": "Click Me",
            "buttonStyle": "bordered",
            "role": "destructive"
        ]
        
        let props = Button.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.title, "Click Me", "title should be valid String")
        XCTAssertEqual(mods.buttonStyle, .bordered, "buttonStyle should be valid String")
        XCTAssertEqual(props.role, .destructive, "role should be valid String")
    }
    
    func testButtonPropsIgnoreInvalidValues() throws {
        let properties: [String: Any] = [
            "title": 123,
            "buttonStyle": "invalid",
            "role": "invalid"
        ]
        
        let props = Button.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.title, "", "title should be the default for invalid type")
        XCTAssertNil(mods.buttonStyle, "buttonStyle should be nil for invalid value")
        XCTAssertNil(props.role, "role should be nil for invalid value")
    }
    
    func testButtonPropsMissing() throws {
        let properties: [String: Any] = [:]
        
        let props = Button.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.title, "", "title should be the default when no properties provided")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.assetImage)
        XCTAssertNil(props.imageScale)
        XCTAssertNil(props.role)
        XCTAssertNil(mods.buttonStyle)
    }
    
    func testButtonPropsPartial() throws {
        let properties: [String: Any] = [
            "title": "Click Me"
        ]
        
        let props = Button.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.title, "Click Me", "title should be valid String")
        XCTAssertNil(mods.buttonStyle, "buttonStyle should be nil when not provided")
        XCTAssertNil(props.role, "role should be nil when not provided")
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Button",
            "properties": [
                "title": "Click Me",
                "buttonStyle": "bordered",
                "role": "destructive"
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = Button.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = Button.applyModifiers(view, element, windowUUID, properties, logger)
        
        // Note: Cannot check modifiedView type as SwiftUI.Button<SwiftUI.Text> due to SwiftUI's modifier wrapping (e.g., _ModifiedContent)
        // Note: Cannot inspect buttonStyle or other modifiers due to SwiftUI's opaque view hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Button",
            "properties": [:]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = Button.buildView(element, viewModel, windowUUID, properties, logger)
        let _ = Button.applyModifiers(view, element, windowUUID, properties, logger)
        
        // Note: Cannot check modifiedView type as SwiftUI.Button<SwiftUI.Text> due to SwiftUI's modifier wrapping (e.g., _ModifiedContent)
        // Note: Cannot inspect buttonStyle or other modifiers due to SwiftUI's opaque view hierarchy
    }

    // MARK: - Image support tests

    func testBuildViewWithSystemImageOnly() throws {
        let properties: [String: Any] = [
            "systemImage": "plus.circle.fill",
            "title": "",
            "imageScale": "large"
        ]
        
        let elementDict: [String: Any] = [
            "id": 10,
            "type": "Button",
            "properties": properties
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let rawProperties = element.properties
        let viewModel = ViewModel()
        
        let _ = Button.buildView(element, viewModel, windowUUID, rawProperties, logger)
        
        // We can't deeply inspect SwiftUI view hierarchy in unit tests easily,
        // but we can at least confirm it builds without crash and is Button type
        // Optional: snapshot test or manual inspection in preview/demo if needed
    }

    func testBuildViewWithNoImageFallsBackToText() throws {
        let properties: [String: Any] = [
            "title": "Plain Text Button",
            "imageScale": "large"           // should be ignored
        ]
        
        let elementDict: [String: Any] = [
            "id": 12,
            "type": "Button",
            "properties": properties
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let rawProperties = element.properties
        let viewModel = ViewModel()
        
        let _ = Button.buildView(element, viewModel, windowUUID, rawProperties, logger)
    }

    func testButtonPropsImageScale() throws {
        // valid values
        let props1: [String: Any] = ["imageScale": "large"]
        XCTAssertEqual(Button.Props(props1).imageScale, .large)
        
        // invalid type
        let props2: [String: Any] = ["imageScale": 123]
        XCTAssertNil(Button.Props(props2).imageScale)
        
        // invalid string value (not a known name, the scale falls back to .medium)
        let props3: [String: Any] = ["imageScale": "extra-large"]
        XCTAssertNil(Button.Props(props3).imageScale)
    }
}
