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
    
    func testGaugeConstructionAndStateBinding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": [
                "value": 0.75,
                "label": "Progress",
                "style": "accessoryLinear",
                "range": ["min": 0.0, "max": 100.0]
            ]
        ]
        let element = try! StaticElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Gauge.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        _ = Gauge.applyModifiers(view, validatedProperties, logger) // Apply gaugeStyle
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        XCTAssertNotNil(state.wrappedValue[element.id], "Registry should initialize state for Gauge")
        
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertEqual(viewState?["value"] as? Double, 0.75, "Gauge state should include value")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                viewState?["validatedProperties"] as? [String: Any] ?? [:],
                validatedProperties
            ),
            "State should include validated properties"
        )
    }
    
    func testGaugeJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": [
                "value": 0.75,
                "label": "Progress",
                "style": "accessoryCircular",
                "range": ["min": 0.0, "max": 100.0]
            ]
        ]
        
        let element = try! StaticElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Gauge", "Element type should be Gauge")
        XCTAssertEqual(element.properties["value"] as? Double, 0.75, "Value should be 0.75")
        XCTAssertEqual(element.properties["label"] as? String, "Progress", "Label should be Progress")
        XCTAssertEqual(element.properties["style"] as? String, "accessoryCircular", "Style should be accessoryCircular")
        XCTAssertEqual((element.properties["range"] as? [String: Double])?["min"], 0.0, "Range min should be 0.0")
        XCTAssertEqual((element.properties["range"] as? [String: Double])?["max"], 100.0, "Range max should be 100.0")
        XCTAssertNil(element.children, "Children should be nil")
    }
    
    func testGaugeValidatePropertiesValid() {
        let properties: [String: Any] = [
            "value": 0.5,
            "label": "Progress",
            "style": "accessoryLinearCapacity",
            "range": ["min": -10.0, "max": 10.0]
        ]
        
        let validated = Gauge.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["value"] as? Double, 0.5, "Value should be valid")
        XCTAssertEqual(validated["label"] as? String, "Progress", "Label should be valid")
        XCTAssertEqual(validated["style"] as? String, "accessoryLinearCapacity", "Style should be valid")
        XCTAssertEqual((validated["range"] as? [String: Double])?["min"], -10.0, "Range min should be valid")
        XCTAssertEqual((validated["range"] as? [String: Double])?["max"], 10.0, "Range max should be valid")
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
        XCTAssertEqual((validated["range"] as? [String: Double])?["min"], 0.0, "Invalid range min should default to 0.0")
        XCTAssertEqual((validated["range"] as? [String: Double])?["max"], 1.0, "Invalid range max should default to 1.0")
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
