// Tests/Views/AsyncImageTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class AsyncImageTests: XCTestCase {
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
    
    func testAsyncImagePropsValid() throws {
        let properties: [String: Any] = [
            "url": "https://example.com/image.jpg",
            "placeholder": "photo.fill",
            "resizable": true,
            "contentMode": "fit"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertEqual(props.url, "https://example.com/image.jpg", "url should be valid String")
        XCTAssertEqual(props.placeholder, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(props.resizable, true, "resizable should be valid Bool")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be valid")
    }
    
    func testAsyncImagePropsIgnoreInvalid() throws {
        let properties: [String: Any] = [
            "url": 123,
            "placeholder": 456,
            "resizable": "true",
            "contentMode": "invalid"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertNil(props.url, "url should be nil for invalid type")
        XCTAssertEqual(props.placeholder, "photo", "placeholder should be the default for invalid type")
        XCTAssertEqual(props.resizable, true, "resizable should be the default for invalid type")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be the default for invalid value")
    }
    
    func testAsyncImagePropsMissing() throws {
        let properties: [String: Any] = [:]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertNil(props.url, "url should be nil when no properties provided")
        XCTAssertEqual(props.placeholder, "photo", "placeholder should be the default when no properties provided")
        XCTAssertEqual(props.resizable, true, "resizable should be the default when no properties provided")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be the default when no properties provided")
    }
    
    func testAsyncImagePropsPartial() throws {
        let properties: [String: Any] = [
            "url": "https://example.com/image.jpg",
            "placeholder": "photo.fill"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertEqual(props.url, "https://example.com/image.jpg", "url should be valid String")
        XCTAssertEqual(props.placeholder, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(props.resizable, true, "resizable should be the default when not provided")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be the default when not provided")
    }
    
    func testAsyncImagePropsInvalidUrl() throws {
        let properties: [String: Any] = [
            "url": "invalid-url",
            "placeholder": "photo.fill",
            "resizable": true,
            "contentMode": "fit"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertEqual(props.url, "invalid-url", "url should pass through as string, even if invalid")
        XCTAssertEqual(props.placeholder, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(props.resizable, true, "resizable should be valid Bool")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be valid")
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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Act: Create ActionUIView
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body // Access the body to trigger view construction

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

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = AsyncImage.buildView(element, viewModel, windowUUID, properties, logger)
        _ = AsyncImage.applyModifiers(view, element, windowUUID, properties, logger)
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

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = AsyncImage.buildView(element, viewModel, windowUUID, properties, logger)
        _ = AsyncImage.applyModifiers(view, element, windowUUID, properties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Image) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
