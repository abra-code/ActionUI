// Tests/Views/ProgressViewTests.swift
/*
 ProgressViewTests.swift

 Tests for the ProgressView component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ProgressViewTests: XCTestCase {
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
    
    func testProgressViewValidatePropertiesValid() {
        let properties: [String: Any] = [
            "value": 0.5,
            "total": 1.0,
            "title": "Loading",
            "actionID": "progress.tap"
        ]
        
        let validated = ProgressView.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["value"] as? Double, 0.5, "value should be valid")
        XCTAssertEqual(validated["total"] as? Double, 1.0, "total should be valid")
        XCTAssertEqual(validated["title"] as? String, "Loading", "title should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "progress.tap", "actionID should be valid")
    }
    
    func testProgressViewValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "value": -0.5,
            "total": 0.0,
            "title": 123
        ]
        
        let validated = ProgressView.validateProperties(properties, logger)
        
        XCTAssertNil(validated["value"], "Invalid value should be nil")
        XCTAssertNil(validated["total"], "Invalid total should be nil")
        XCTAssertNil(validated["title"], "Invalid title should be nil")
    }
    
    func testProgressViewValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = ProgressView.validateProperties(properties, logger)
        
        XCTAssertNil(validated["value"], "Missing value should be nil")
        XCTAssertNil(validated["total"], "Missing total should be nil")
        XCTAssertNil(validated["title"], "Missing title should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    func testProgressViewConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ProgressView",
            "properties": [
                "value": 0.5,
                "total": 1.0,
                "title": "Loading",
                "actionID": "progress.tap",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = ProgressView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testProgressViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ProgressView",
            "properties": {
                "value": 0.5,
                "total": 1.0,
                "title": "Loading",
                "actionID": "progress.tap",
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
        XCTAssertEqual(element.type, "ProgressView", "Element type should be ProgressView")
        XCTAssertEqual(element.properties.double(forKey: "value"), 0.5, "value should be 0.5")
        XCTAssertEqual(element.properties.double(forKey: "total"), 1.0, "total should be 1.0")
        XCTAssertEqual(element.properties["title"] as? String, "Loading", "title should be Loading")
        XCTAssertEqual(element.properties["actionID"] as? String, "progress.tap", "actionID should be progress.tap")
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
        XCTAssertEqual(viewModel.value as? Double, 0.5, "Initial viewModel value should be 0.5")
    }
}
