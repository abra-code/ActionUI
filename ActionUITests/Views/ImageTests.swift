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
    
    func testImageConstruction() {
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
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Image.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        XCTAssertTrue(view is SwiftUI.Image, "View should be an Image")
    }
    
    func testImageJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Image",
            "properties": [
                "systemName": "star.fill",
                "resizable": true,
                "scaleMode": "fit",
                "padding": 10.0,
                "offset": ["x": 5.0, "y": -5.0]
            ]
        ]
        
        let element = try! ViewElement(from: elementDict, logger: logger)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "star.fill", "systemName should be star.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, true, "resizable should be true")
        XCTAssertEqual(element.properties["scaleMode"] as? String, "fit", "scaleMode should be fit")
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
            "padding": 10.0
        ]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["systemName"] as? String, "star.fill", "systemName should be preserved")
        XCTAssertEqual(validated["resizable"] as? Bool, true, "resizable should be preserved")
        XCTAssertEqual(validated["scaleMode"] as? String, "fit", "scaleMode should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testImageValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "systemName": 123,
            "resizable": "true",
            "scaleMode": "invalid",
            "filePath": "/path/to/doc.txt"
        ]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertNil(validated["systemName"], "Invalid systemName should be nil")
        XCTAssertNil(validated["resizable"], "Invalid resizable should be nil")
        XCTAssertNil(validated["scaleMode"], "Invalid scaleMode should be nil")
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
    }
    
    func testImageValidatePropertiesFilePathValid() {
        let properties: [String: Any] = [
            "filePath": "/path/to/image.jpg",
            "resizable": false,
            "scaleMode": "fill"
        ]
        
        let validated = Image.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["filePath"] as? String, "/path/to/image.jpg", "Valid filePath should be preserved")
        XCTAssertEqual(validated["resizable"] as? Bool, false, "resizable should be preserved")
        XCTAssertEqual(validated["scaleMode"] as? String, "fill", "scaleMode should be preserved")
    }
}
