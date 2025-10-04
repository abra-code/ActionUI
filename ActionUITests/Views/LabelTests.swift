// Tests/Views/LabelTests.swift
/*
 LabelTests.swift

 Tests for the Label component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LabelTests: XCTestCase {
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
    
    func testLabelConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Label",
            "properties": [
                "title": "Title",
                "systemImage": "star.fill",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Label.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)        
    }
    
    func testLabelJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Label",
            "properties": {
                "title": "Title",
                "systemImage": "star.fill",
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
        XCTAssertEqual(element.type, "Label", "Element type should be Label")
        XCTAssertEqual(element.properties["title"] as? String, "Title", "title should be Title")
        XCTAssertEqual(element.properties["systemImage"] as? String, "star.fill", "systemImage should be star.fill")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testLabelValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Title",
            "systemImage": "star.fill",
            "padding": 10.0
        ]
        
        let validated = Label.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Title", "title should be preserved")
        XCTAssertEqual(validated["systemImage"] as? String, "star.fill", "systemImage should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testLabelValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "systemImage": 456,
            "imageName": true
        ]
        
        let validated = Label.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Invalid title should be nil")
        XCTAssertNil(validated["systemImage"], "Invalid systemImage should be nil")
        XCTAssertNil(validated["imageName"], "Invalid imageName should be nil")
    }
    
    func testLabelValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Label.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
        XCTAssertNil(validated["systemImage"], "Missing systemImage should be nil")
        XCTAssertNil(validated["imageName"], "Missing imageName should be nil")
    }
    
    func testLabelValidatePropertiesTitleOnly() {
        let properties: [String: Any] = [
            "title": "Title"
        ]
        
        let validated = Label.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Title", "title should be preserved")
        XCTAssertNil(validated["systemImage"], "Missing systemImage should be nil")
        XCTAssertNil(validated["imageName"], "Missing imageName should be nil")
    }
    
    func testLabelValidatePropertiesImageName() {
        let properties: [String: Any] = [
            "title": "Title",
            "imageName": "customIcon"
        ]
        
        let validated = Label.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Title", "title should be preserved")
        XCTAssertNil(validated["systemImage"], "Missing systemImage should be nil")
        XCTAssertEqual(validated["imageName"] as? String, "customIcon", "imageName should be preserved")
    }
}
