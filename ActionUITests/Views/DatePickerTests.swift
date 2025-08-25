// Tests/Views/DatePickerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DatePickerTests: XCTestCase {
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
        if let range = validated["range"] as? [String: Date] {
            let formatter = ISO8601DateFormatter()
            XCTAssertNotNil(range["start"], "range.start should be valid Date")
            XCTAssertNotNil(range["end"], "range.end should be valid Date")
            XCTAssertEqual(formatter.string(from: range["start"]!), "2023-01-01T00:00:00Z", "range.start should match")
            XCTAssertEqual(formatter.string(from: range["end"]!), "2025-12-31T00:00:00Z", "range.end should match")
        } else {
            XCTFail("range should be valid [String: Date]")
        }
        if let selectedDate = validated["selectedDate"] as? Date {
            let formatter = ISO8601DateFormatter()
            XCTAssertEqual(formatter.string(from: selectedDate), "2024-07-16T00:00:00Z", "selectedDate should be valid Date")
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
        XCTAssertNil(validated["range"], "range should be nil for invalid start date")
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
        if let selectedDate = validated["selectedDate"] as? Date {
            let formatter = ISO8601DateFormatter()
            XCTAssertEqual(formatter.string(from: selectedDate), "2024-07-16T00:00:00Z", "selectedDate should be valid Date")
        } else {
            XCTFail("selectedDate should be valid Date")
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
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        
        let view = DatePicker.buildView(element, state, UUID().uuidString, validatedProperties, logger)
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
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        
        let view = DatePicker.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        _ = DatePicker.applyModifiers(view, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testDatePickerStateBinding() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DatePicker",
            "properties": [
                "label": "Select Date",
                "selectedDate": "2024-07-16T00:00:00Z"
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        
        let _ = DatePicker.buildView(element, state, UUID().uuidString, validatedProperties, logger)
        
        // Verify state initialization
        let viewState = state.wrappedValue[element.id] as? [String: Any]
        XCTAssertNotNil(viewState, "State should be initialized for DatePicker")
        XCTAssertNotNil(viewState?["value"] as? Date, "DatePicker state should include a Date value")
        if let stateValue = viewState?["value"] as? Date, let selectedDate = validatedProperties["selectedDate"] as? Date {
            XCTAssertEqual(stateValue, selectedDate, "State value should match selectedDate")
        } else {
            XCTFail("State value or selectedDate should be valid Date")
        }
        guard let stateProperties = viewState?["validatedProperties"] as? [String: Any] else {
            XCTFail("State validatedProperties should be a [String: Any] dictionary")
            return
        }
        // Explicitly compare Date values to diagnose comparison issue
        if let stateDate = stateProperties["selectedDate"] as? Date, let expectedDate = validatedProperties["selectedDate"] as? Date {
            XCTAssertEqual(stateDate, expectedDate, "State selectedDate should match expected selectedDate")
        } else {
            XCTFail("State or expected selectedDate should be valid Date")
        }
        // Sort keys to handle key order sensitivity
        let stateKeys = stateProperties.keys.sorted()
        let validatedKeys = validatedProperties.keys.sorted()
        guard stateKeys == validatedKeys else {
            print("State keys: \(stateKeys)")
            print("Expected keys: \(validatedKeys)")
            XCTFail("State and validated properties should have the same keys")
            return
        }
        var areEqual = true
        for key in stateKeys {
            if key == "selectedDate" {
                if let stateDate = stateProperties[key] as? Date, let validatedDate = validatedProperties[key] as? Date {
                    areEqual = areEqual && (stateDate == validatedDate)
                } else {
                    areEqual = false
                }
            } else if let stateValue = stateProperties[key] as? String, let validatedValue = validatedProperties[key] as? String {
                areEqual = areEqual && (stateValue == validatedValue)
            } else {
                areEqual = false
            }
            if !areEqual {
                break
            }
        }
        if !areEqual {
            print("State validatedProperties: \(String(describing: stateProperties))")
            print("Expected validatedProperties: \(String(describing: validatedProperties))")
            XCTFail("State validatedProperties do not match expected validatedProperties")
        }
        XCTAssertTrue(areEqual, "State should include validated properties")
    }
}
