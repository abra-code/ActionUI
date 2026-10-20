// Tests/Views/LinkTests.swift
/*
 LinkTests.swift

 Tests for the Link component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LinkTests: XCTestCase {
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
    
    func testLinkConstructionValidURL() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Link",
            "properties": [
                "title": "Visit Site",
                "url": "https://example.com",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element,  model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After viewBuild: viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.Link<SwiftUI.Text>, "View should be a Link with Text label")
    }
    
    func testLinkConstructionInvalidURL() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Link",
            "properties": [
                "title": "Visit Site",
                "url": "invalid-url"
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After viewBuild: viewModel = \(String(describing: viewModel))", .debug)
        // Swift's URL() does not fail when initialized with a string like "invalid-url"
        XCTAssertTrue(view is SwiftUI.Link<SwiftUI.Text>, "View should be a Link with Text label for invalid URL string")
    }
    
    func testLinkJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Link",
            "properties": {
                "title": "Visit Site",
                "url": "https://example.com",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Link", "Element type should be Link")
        XCTAssertEqual(element.properties["title"] as? String, "Visit Site", "title should be Visit Site")
        XCTAssertEqual(element.properties["url"] as? String, "https://example.com", "url should be https://example.com")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testLinkPropsValid() {
        let properties: [String: Any] = [
            "title": "Visit Site",
            "url": "https://example.com",
            "padding": 10.0
        ]
        
        let props = Link.Props(properties)
        
        XCTAssertEqual(props.title, "Visit Site", "title should be preserved")
        XCTAssertEqual(props.url, "https://example.com", "url should be preserved")
        XCTAssertEqual(BaseModifiers(properties).padding, .uniform(10.0), "padding should be passed through")
    }
    
    func testLinkPropsIgnoreInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "url": 456
        ]
        
        let props = Link.Props(properties)
        
        XCTAssertEqual(props.title, "Link", "Invalid title should be ignored")
        XCTAssertNil(props.url, "Invalid url should be ignored")
    }
    
    func testLinkPropsInvalidURL() {
        let properties: [String: Any] = [
            "title": "Visit Site",
            "url": "invalid-url"
        ]
        
        let props = Link.Props(properties)
        
        XCTAssertEqual(props.title, "Visit Site", "title should be preserved")
        XCTAssertEqual(props.url, "invalid-url", "url should be preserved as a valid string")
    }
    
    func testLinkPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Link.Props(properties)
        
        XCTAssertEqual(props.title, "Link", "Missing title should be the default")
        XCTAssertNil(props.url, "Missing url should be nil")
    }
    
    func testLinkPropsTitleOnly() {
        let properties: [String: Any] = [
            "title": "Visit Site"
        ]
        
        let props = Link.Props(properties)
        
        XCTAssertEqual(props.title, "Visit Site", "title should be preserved")
        XCTAssertNil(props.url, "Missing url should be nil")
    }
}
