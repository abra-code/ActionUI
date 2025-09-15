/*
 SliderTests.swift

 Tests for the Slider component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SliderTests: XCTestCase {
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
    
    func testSliderJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Slider",
            "properties": {
                "value": 50.0,
                "range": {"min": 0.0, "max": 100.0},
                "step": 1.0
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
        XCTAssertEqual(element.type, "Slider", "Element type should be Slider")
        XCTAssertEqual(element.properties.double(forKey: "value"), 50.0, "Value should be 50.0")
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "min"), 0.0, "Range min should be 0.0")
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "max"), 100.0, "Range max should be 100.0")
        XCTAssertEqual(element.properties.double(forKey: "step"), 1.0, "Step should be 1.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testSliderJSONDecodingWithIntValues() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Slider",
            "properties": {
                "value": 50,
                "range": {"min": 0, "max": 100},
                "step": 1
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
        XCTAssertEqual(element.type, "Slider", "Element type should be Slider")
        XCTAssertEqual(element.properties.double(forKey: "value"), 50.0, "Value should be 50.0")
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "min"), 0.0, "Range min should be 0.0")
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "max"), 100.0, "Range max should be 100.0")
        XCTAssertEqual(element.properties.double(forKey: "step"), 1.0, "Step should be 1.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testSliderValidatePropertiesValid() {
        let properties: [String: Any] = [
            "value": 0.5,
            "range": ["min": -10.0, "max": 10.0],
            "step": 2.0
        ]
        
        let validated = Slider.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.double(forKey: "value"), 0.5, "Value should be valid")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "min"), -10.0, "Range min should be valid")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "max"), 10.0, "Range max should be valid")
        XCTAssertEqual(validated.double(forKey: "step"), 2.0, "Step should be valid")
    }
    
    func testSliderValidatePropertiesInvalidStepLargerThanRange() {
        let properties: [String: Any] = [
            "value": 5.0,
            "range": ["min": 0.0, "max": 10.0],
            "step": 20.0
        ]
        
        let validated = Slider.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.double(forKey: "value"), 5.0, "Value should be valid")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "min"), 0.0, "Range min should be valid")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "max"), 10.0, "Range max should be valid")
        XCTAssertEqual(validated.double(forKey: "step"), 10.0, "Step should be clamped to range (max - min)")
    }
    
    func testSliderValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = [
            "value": "0.5",
            "range": ["min": "0", "max": true],
            "step": "1.0"
        ]
        
        let validated = Slider.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.double(forKey: "value"), 0.0, "Invalid value should default to 0.0")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "min"), 0.0, "Invalid range min should default to 0.0")
        XCTAssertEqual((validated["range"] as? [String: Any])?.double(forKey: "max"), 1.0, "Invalid range max should default to 1.0")
        XCTAssertEqual(validated.double(forKey: "step"), 1.0, "Invalid step should default to 1.0")
    }
    
    func testSliderValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Slider.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.double(forKey: "value"), 0.0, "Missing value should default to 0.0")
        XCTAssertNil(validated["range"], "Missing range should be nil")
        XCTAssertNil(validated["step"], "Missing step should be nil")
    }
    
    func testSliderViewConstructionAndBinding() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Slider",
            "properties": [
                "value": 50.0,
                "range": ["min": 0.0, "max": 100.0],
                "step": 10.0,
                "valueChangeActionID": "slider.changed"
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        
        // Retrieve view model
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        // Create ActionUIView
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body // Access body to trigger view construction
        
        // Verify initial value
        XCTAssertEqual(viewModel.value as? Double, 50.0, "Initial value should be 50.0")
        
        // Note: Accessing actionUIView.body may produce a runtime warning as the view is not embedded
        // Note: Binding, action triggering, and clamping tests are handled in XCUITests
        // Note: Avoid strict type checks (e.g., SwiftUI.Slider) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
    }
}
