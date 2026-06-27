// Tests/Views/DatePickerTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class DatePickerTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testValidatePropertiesValid() throws {
        let properties: [String: Any] = [
            "title": "Select Date",
            "displayStyle": "compact",
            "range": ["start": "2023-01-01T00:00:00Z", "end": "2025-12-31T00:00:00Z"],
            "selectedDate": "2024-07-16T00:00:00Z"
        ]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Select Date", "title should be valid String")
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
            "title": 123,
            "displayStyle": "invalid",
            "range": ["start": "invalid", "end": "2025-12-31T00:00:00Z"],
            "selectedDate": true
        ]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "title should be nil for invalid type")
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
            "title": "Select Date",
            "selectedDate": "2024-07-16T00:00:00Z"
        ]
        
        let validated = DatePicker.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Select Date", "title should be valid String")
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
                "title": "Select Date",
                "displayStyle": "compact",
                "range": ["start": "2023-01-01T00:00:00Z", "end": "2025-12-31T00:00:00Z"],
                "selectedDate": "2024-07-16T00:00:00Z"
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = DatePicker.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = DatePicker.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect DatePicker state or modifiers due to SwiftUI's opaque hierarchy
    }
    
    // MARK: - displayedComponents

    func testValidateDisplayedComponentsValid() throws {
        for value in ["date", "hourAndMinute", "dateAndTime"] {
            let validated = DatePicker.validateProperties(["displayedComponents": value], logger)
            XCTAssertEqual(validated["displayedComponents"] as? String, value, "\(value) should pass through")
        }
    }

    func testValidateDisplayedComponentsInvalid() throws {
        let validated = DatePicker.validateProperties(["displayedComponents": "wheel"], logger)
        XCTAssertNil(validated["displayedComponents"], "unknown displayedComponents should be dropped")
        let nonString = DatePicker.validateProperties(["displayedComponents": 7], logger)
        XCTAssertNil(nonString["displayedComponents"], "non-string displayedComponents should be dropped")
    }

    func testDisplayedComponentsMapping() throws {
        XCTAssertEqual(DatePicker.displayedComponents(from: nil), .date)
        XCTAssertEqual(DatePicker.displayedComponents(from: "date"), .date)
        XCTAssertEqual(DatePicker.displayedComponents(from: "hourAndMinute"), .hourAndMinute)
        XCTAssertEqual(DatePicker.displayedComponents(from: "dateAndTime"), [.date, .hourAndMinute])
    }

    func testIsTimeBearing() throws {
        XCTAssertFalse(DatePicker.isTimeBearing(nil))
        XCTAssertFalse(DatePicker.isTimeBearing("date"))
        XCTAssertTrue(DatePicker.isTimeBearing("hourAndMinute"))
        XCTAssertTrue(DatePicker.isTimeBearing("dateAndTime"))
    }

    // MARK: - DateHelper value formatting

    func testFormatDateIsBareDate() throws {
        // Noon in current timezone so the date component is stable.
        var c = DateComponents(); c.year = 2024; c.month = 7; c.day = 16; c.hour = 12
        let date = Calendar.current.date(from: c)!
        XCTAssertEqual(DateHelper.formatDate(from: date), "2024-07-16")
    }

    func testFormatDateTimeIsFullLocalISO() throws {
        var c = DateComponents()
        c.year = 2024; c.month = 7; c.day = 16; c.hour = 9; c.minute = 5; c.second = 0
        let date = Calendar.current.date(from: c)!
        XCTAssertEqual(DateHelper.formatDateTime(from: date), "2024-07-16T09:05:00")
    }

    func testParseLocalTimeSeedsTodayWithChosenTime() throws {
        let parsed = DateHelper.parseDate(from: "14:30")
        XCTAssertNotNil(parsed)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: parsed!)
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        XCTAssertEqual(parts.year, today.year)
        XCTAssertEqual(parts.month, today.month)
        XCTAssertEqual(parts.day, today.day)
        XCTAssertEqual(parts.hour, 14)
        XCTAssertEqual(parts.minute, 30)
    }

    func testParseFullDateTimeRoundTrips() throws {
        let parsed = DateHelper.parseDate(from: "2024-07-16T09:05:00")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(DateHelper.formatDateTime(from: parsed!), "2024-07-16T09:05:00")
    }

    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DatePicker",
            "properties": [:]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = DatePicker.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = DatePicker.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        _ = DatePicker.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
