// Tests/Views/DatePickerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DatePickerTests: XCTestCase {
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
    
    func testValidatePropertiesValid() throws {
        let properties: [String: Any] = [
            "label": "Select Date",
            "displayStyle": "compact",
            "range": ["start": "2023-01-01T00:00:00Z", "end": "2025-12-31T00:00:00Z"],
            "selectedDate": "2024-07-16T00:00:00Z"
        ]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["label"] as? String, "Select Date", "label should be valid String")
        XCTAssertEqual(validated["displayStyle"] as? String, "compact", "displayStyle should be valid String")
        if let range = validated["range"] as? [String: String] {
            XCTAssertNotNil(range["start"], "range.start should be valid Date string")
            XCTAssertNotNil(range["end"], "range.end should be valid Date string")
            XCTAssertEqual(range["start"], "2023-01-01T00:00:00Z", "range.start should match")
            XCTAssertEqual(range["end"], "2025-12-31T00:00:00Z", "range.end should match")
        } else {
            XCTFail("range should be valid [String: String]")
        }
        if let selectedDate = validated["selectedDate"] as? String {
            XCTAssertEqual(selectedDate, "2024-07-16T00:00:00Z", "selectedDate should be valid Date")
        } else {
            XCTFail("selectedDate should be valid Date")
        }
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "label": 123,
            "displayStyle": "invalid",
            "range": ["start": "invalid", "end": "2025-12-31T00:00:00Z"],
            "selectedDate": true
        ]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertNil(validated["label"], "label should be nil for invalid type")
        XCTAssertNil(validated["displayStyle"], "displayStyle should be nil for invalid value")
        // validateProperties is lightweight, it does not check if the string is a valid date
        XCTAssertNil(validated["selectedDate"], "selectedDate should be nil for invalid type")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "label": "Select Date",
            "selectedDate": "2024-07-16T00:00:00Z"
        ]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["label"] as? String, "Select Date", "label should be valid String")
        XCTAssertNil(validated["displayStyle"], "displayStyle should be nil when not provided")
        XCTAssertNil(validated["range"], "range should be nil when not provided")
        if let selectedDate = validated["selectedDate"] as? String {
            XCTAssertEqual(selectedDate, "2024-07-16T00:00:00Z", "selectedDate should be valid Date")
        } else {
            XCTFail("selectedDate should be valid Date string")
        }
    }
    
    func testBuildViewAndApplyModifiersValidProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DatePicker",
            "properties": [
                "label": "Select Date",
                "displayStyle": "compact",
                "range": ["start": "2023-01-01T00:00:00Z", "end": "2025-12-31T00:00:00Z"],
                "selectedDate": "2024-07-16T00:00:00Z"
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = DatePicker.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = DatePicker.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect DatePicker state or modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DatePicker",
            "properties": [:]
        ]

        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = DatePicker.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = DatePicker.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
