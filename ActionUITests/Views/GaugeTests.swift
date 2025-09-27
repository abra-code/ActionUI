// Tests/Views/GaugeTests.swift
/*
 GaugeTests.swift

 Tests for the Gauge component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and gauge style application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class GaugeTests: XCTestCase {
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
        
    func testGaugeJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Gauge",
            "properties": {
                "value": 0.75,
                "label": "Progress",
                "style": "accessoryCircular",
                "range": {"min": 0.0, "max": 100.0}
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
        XCTAssertEqual(element.type, "Gauge", "Element type should be Gauge")
        XCTAssertEqual(element.properties.double(forKey: "value"), 0.75, "Value should be 0.75")
        XCTAssertEqual(element.properties["label"] as? String, "Progress", "Label should be Progress")
        XCTAssertEqual(element.properties["style"] as? String, "accessoryCircular", "Style should be accessoryCircular")
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "min"), 0.0, "Range min should be 0.0")
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "max"), 100.0, "Range max should be 100.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testGaugeValidatePropertiesValid() {
        let properties: [String: Any] = [
            "value": 0.5,
            "label": "Progress",
            "style": "accessoryLinearCapacity",
            "range": ["min": -10.0, "max": 10.0]
        ]
        
        let validated = Gauge.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.double(forKey: "value"), 0.5, "Value should be valid")
        XCTAssertEqual(validated["label"] as? String, "Progress", "Label should be valid")
        XCTAssertEqual(validated["style"] as? String, "accessoryLinearCapacity", "Style should be valid")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "min"), -10.0, "Range min should be valid")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "max"), 10.0, "Range max should be valid")
    }
    
    func testGaugeValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "value": "0.5",
            "label": 123,
            "style": "invalidStyle",
            "range": ["min": "0", "max": true]
        ]
        
        let validated = Gauge.validateProperties(properties, logger)
        
        XCTAssertNil(validated.double(forKey: "value"), "Invalid value should default to nil")
        XCTAssertNil(validated["label"], "Invalid label should be nil")
        XCTAssertNil(validated["style"], "Invalid style should be nil")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "min"), 0.0, "Invalid range min should default to 0.0")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "max"), 1.0, "Invalid range max should default to 1.0")
    }
    
    func testGaugeValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Gauge.validateProperties(properties, logger)
        
        XCTAssertNil(validated["value"], "Missing value should be nil")
        XCTAssertNil(validated["label"], "Missing label should be nil")
        XCTAssertNil(validated["style"], "Missing style should be nil")
        XCTAssertNil(validated["range"], "Missing range should be nil")
    }
}
