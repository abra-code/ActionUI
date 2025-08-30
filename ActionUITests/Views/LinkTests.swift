// Tests/Views/LinkTests.swift
/*
 LinkTests.swift

 Tests for the Link component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LinkTests: XCTestCase {
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
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = Link.validateProperties(element.properties, logger)
        let viewModel = ViewModel(properties: element.properties)
        let view = ActionUIRegistry.shared.buildView(for: element,  model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
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
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = Link.validateProperties(element.properties, logger)
        let viewModel = ViewModel(properties: element.properties)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
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
    
    func testLinkValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Visit Site",
            "url": "https://example.com",
            "padding": 10.0
        ]
        
        let validated = Link.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Visit Site", "title should be preserved")
        XCTAssertEqual(validated["url"] as? String, "https://example.com", "url should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testLinkValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "url": 456
        ]
        
        let validated = Link.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Invalid title should be nil")
        XCTAssertNil(validated["url"], "Invalid url should be nil")
    }
    
    func testLinkValidatePropertiesInvalidURL() {
        let properties: [String: Any] = [
            "title": "Visit Site",
            "url": "invalid-url"
        ]
        
        let validated = Link.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Visit Site", "title should be preserved")
        XCTAssertEqual(validated["url"] as? String, "invalid-url", "url should be preserved as a valid string")
    }
    
    func testLinkValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Link.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
        XCTAssertNil(validated["url"], "Missing url should be nil")
    }
    
    func testLinkValidatePropertiesTitleOnly() {
        let properties: [String: Any] = [
            "title": "Visit Site"
        ]
        
        let validated = Link.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Visit Site", "title should be preserved")
        XCTAssertNil(validated["url"], "Missing url should be nil")
    }
}
