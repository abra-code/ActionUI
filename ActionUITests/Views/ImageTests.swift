// Tests/Views/ImageTests.swift
/*
 ImageTests.swift

 Tests for the Image component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ImageTests: XCTestCase {
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
    
    func testImageConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Image",
            "properties": [
                "systemName": "star.fill",
                "resizable": true,
                "scaleMode": "fit",
                "padding": 10.0
            ]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Image.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should be an EmptyView")
    }
    
    func testImageJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Image",
            "properties": {
                "systemName": "star.fill",
                "resizable": true,
                "scaleMode": "fit",
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
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "star.fill", "systemName should be star.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, true, "resizable should be true")
        XCTAssertEqual(element.properties["scaleMode"] as? String, "fit", "scaleMode should be fit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testImageValidatePropertiesValid() {
        let properties: [String: Any] = [
            "systemName": "star.fill",
            "resizable": true,
            "scaleMode": "fit",
            "imageScale": "large",
            "padding": 10.0
        ]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["systemName"] as? String, "star.fill", "systemName should be preserved")
        XCTAssertEqual(validated["resizable"] as? Bool, true, "resizable should be preserved")
        XCTAssertEqual(validated["scaleMode"] as? String, "fit", "scaleMode should be preserved")
        XCTAssertEqual(validated["imageScale"] as? String, "large", "imageScale should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testImageValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "systemName": 123,
            "resizable": "true",
            "scaleMode": "invalid",
            "imageScale": "huge",
            "filePath": "/path/to/doc.txt"
        ]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertNil(validated["systemName"], "Invalid systemName should be nil")
        XCTAssertNil(validated["resizable"], "Invalid resizable should be nil")
        XCTAssertNil(validated["scaleMode"], "Invalid scaleMode should be nil")
        XCTAssertNil(validated["imageScale"], "Invalid imageScale should be nil")
        XCTAssertNil(validated["filePath"], "Invalid filePath should be nil")
    }
    
    func testImageValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Empty properties should result in empty validated properties")
        XCTAssertNil(validated["systemName"], "Missing systemName should be nil")
        XCTAssertNil(validated["name"], "Missing name should be nil")
        XCTAssertNil(validated["filePath"], "Missing filePath should be nil")
        XCTAssertNil(validated["resizable"], "Missing resizable should be nil")
        XCTAssertNil(validated["scaleMode"], "Missing scaleMode should be nil")
        XCTAssertNil(validated["imageScale"], "Missing imageScale should be nil")
    }
    
    func testImageValidatePropertiesFilePathValid() {
        let properties: [String: Any] = [
            "filePath": "/path/to/image.jpg",
            "resizable": false,
            "scaleMode": "fill",
            "imageScale": "small"
        ]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["filePath"] as? String, "/path/to/image.jpg", "Valid filePath should be preserved")
        XCTAssertEqual(validated["resizable"] as? Bool, false, "resizable should be preserved")
        XCTAssertEqual(validated["scaleMode"] as? String, "fill", "scaleMode should be preserved")
        XCTAssertEqual(validated["imageScale"] as? String, "small", "imageScale should be preserved")
    }
    
    func testImageJSONDecodingWithImageScale() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Image",
            "properties": {
                "systemName": "heart.fill",
                "resizable": false,
                "imageScale": "small",
                "padding": 5.0
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
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "heart.fill", "systemName should be heart.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, false, "resizable should be false")
        XCTAssertEqual(element.properties["imageScale"] as? String, "small", "imageScale should be small")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 5.0, "padding should be 5.0")
    }
}
