// Tests/Views/ShareLinkTests.swift
/*
 ShareLinkTests.swift

 Tests for the ShareLink component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ShareLinkTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
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
    
    func testShareLinkValidatePropertiesValid() {
        let properties: [String: Any] = [
            "item": "https://example.com",
            "subject": "Check this out",
            "message": "Look at this link!",
            "padding": 10.0
        ]
        
        let validated = ShareLink.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["item"] as? String, "https://example.com", "item should be valid")
        XCTAssertEqual(validated["subject"] as? String, "Check this out", "subject should be valid")
        XCTAssertEqual(validated["message"] as? String, "Look at this link!", "message should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testShareLinkValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "item": "invalid-url",
            "subject": 123,
            "message": true
        ]
        
        let validated = ShareLink.validateProperties(properties, logger)
        
        // creating URL("invalid-url") is not nil
        // XCTAssertNil(validated["item"], "Invalid URL item should be nil")
        
        XCTAssertNil(validated["subject"], "Invalid subject should be nil")
        XCTAssertNil(validated["message"], "Invalid message should be nil")
    }
    
    func testShareLinkValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = ShareLink.validateProperties(properties, logger)
        
        XCTAssertNil(validated["item"], "Missing item should be nil")
        XCTAssertNil(validated["subject"], "Missing subject should be nil")
        XCTAssertNil(validated["message"], "Missing message should be nil")
    }
    
    func testShareLinkConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ShareLink",
            "properties": [
                "item": "https://example.com",
                "subject": "Check this out",
                "message": "Look at this link!",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ShareLink.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testShareLinkJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ShareLink",
            "properties": {
                "item": "https://example.com",
                "subject": "Check this out",
                "message": "Look at this link!",
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
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "ShareLink", "Element type should be ShareLink")
        XCTAssertEqual(element.properties["item"] as? String, "https://example.com", "item should be https://example.com")
        XCTAssertEqual(element.properties["subject"] as? String, "Check this out", "subject should be Check this out")
        XCTAssertEqual(element.properties["message"] as? String, "Look at this link!", "message should be Look at this link!")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.value, "Initial viewModel value should be nil for ShareLink")
    }
}
