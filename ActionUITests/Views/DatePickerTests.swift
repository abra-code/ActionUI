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
    
    func testDatePickerPropsValid() throws {
        let properties: [String: Any] = [
            "title": "Select Date",
            "displayStyle": "compact",
            "range": ["start": "2023-01-01T00:00:00Z", "end": "2025-12-31T00:00:00Z"],
            "selectedDate": "2024-07-16T00:00:00Z"
        ]
        
        let props = DatePicker.Props(properties)
        
        XCTAssertEqual(props.title, "Select Date", "title should be valid String")
        XCTAssertEqual(props.displayStyle, .compact, "displayStyle should be valid String")
        if let range = props.range {
            XCTAssertEqual(range.start, "2023-01-01T00:00:00Z", "range.start should match")
            XCTAssertEqual(range.end, "2025-12-31T00:00:00Z", "range.end should match")
        } else {
            XCTFail("range should be valid [String: String]")
        }
        XCTAssertEqual(props.selectedDate, "2024-07-16T00:00:00Z", "selectedDate should be valid Date")
    }
    
    func testDatePickerPropsIgnoreInvalidValues() throws {
        let properties: [String: Any] = [
            "title": 123,
            "displayStyle": "invalid",
            "range": ["start": "invalid", "end": "2025-12-31T00:00:00Z"],
            "selectedDate": true
        ]
        
        let props = DatePicker.Props(properties)
        
        XCTAssertEqual(props.title, "Date", "title should be the default for invalid type")
        XCTAssertNil(props.displayStyle, "displayStyle should be nil for invalid value")
        // Props is lightweight, it does not check if the string is a valid date
        XCTAssertEqual(props.selectedDate, "", "selectedDate should be the default for invalid type")
    }
    
    func testDatePickerPropsMissing() throws {
        let properties: [String: Any] = [:]
        
        let props = DatePicker.Props(properties)
        
        XCTAssertEqual(props.title, "Date", "title should be the default when no properties provided")
        XCTAssertNil(props.displayStyle)
        XCTAssertNil(props.displayedComponents)
        XCTAssertNil(props.range)
        XCTAssertEqual(props.selectedDate, "")
        XCTAssertNil(props.valueChangeActionID)
    }
    
    func testDatePickerPropsPartial() throws {
        let properties: [String: Any] = [
            "title": "Select Date",
            "selectedDate": "2024-07-16T00:00:00Z"
        ]
        
        let props = DatePicker.Props(properties)
        
        XCTAssertEqual(props.title, "Select Date", "title should be valid String")
        XCTAssertNil(props.displayStyle, "displayStyle should be nil when not provided")
        XCTAssertNil(props.range, "range should be nil when not provided")
        XCTAssertEqual(props.selectedDate, "2024-07-16T00:00:00Z", "selectedDate should be valid Date")
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
        let properties = element.properties
        let viewModel = ViewModel()
        let view = DatePicker.buildView(element, viewModel, windowUUID, properties, logger)
        _ = DatePicker.applyModifiers(view, element, windowUUID, properties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect DatePicker state or modifiers due to SwiftUI's opaque hierarchy
    }
    
    // MARK: - displayedComponents

    func testDatePickerPropsDisplayedComponentsValid() throws {
        let expected: [(String, ActionUI.DatePicker.Props.DisplayedComponents)] = [("date", .date), ("hourAndMinute", .hourAndMinute), ("dateAndTime", .dateAndTime)]
        for (value, components) in expected {
            let props = DatePicker.Props(["displayedComponents": value])
            XCTAssertEqual(props.displayedComponents, components, "\(value) should pass through")
        }
    }

    func testDatePickerPropsDisplayedComponentsInvalid() throws {
        let props = DatePicker.Props(["displayedComponents": "wheel"])
        XCTAssertNil(props.displayedComponents, "unknown displayedComponents should be ignored")
        let nonString = DatePicker.Props(["displayedComponents": 7])
        XCTAssertNil(nonString.displayedComponents, "non-string displayedComponents should be ignored")
    }

    func testDisplayedComponentsMapping() throws {
        XCTAssertEqual(DatePicker.displayedComponents(from: nil), .date)
        XCTAssertEqual(DatePicker.displayedComponents(from: "date"), .date)
        XCTAssertEqual(DatePicker.displayedComponents(from: "hourAndMinute"), .hourAndMinute)
        XCTAssertEqual(DatePicker.displayedComponents(from: "dateAndTime"), [.date, .hourAndMinute])
    }

    func testIsTimeBearing() throws {
        XCTAssertFalse(DateHelper.isTimeBearing(nil))
        XCTAssertFalse(DateHelper.isTimeBearing("date"))
        XCTAssertTrue(DateHelper.isTimeBearing("hourAndMinute"))
        XCTAssertTrue(DateHelper.isTimeBearing("dateAndTime"))
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

    // MARK: - Time zones (instants, wall-clock time, calendar days)

    // Runs body with the process time zone set to `identifier`, restoring it after.
    private func inZone(_ identifier: String, _ body: () throws -> Void) rethrows {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier)!
        defer { NSTimeZone.default = saved }
        try body()
    }

    private func localComponents(_ date: Date?) -> DateComponents? {
        date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
    }

    // 2024-07-16T14:30:00Z
    private let instant1430Z = Date(timeIntervalSince1970: 1_721_140_200)

    func testParseHonorsZoneDesignators() throws {
        // The device zone must not matter for a zoned string.
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "UTC"] {
            inZone(zone) {
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T14:30:00Z"), instant1430Z, zone)
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T16:30:00+02:00"), instant1430Z, zone)
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T09:30:00-05:00"), instant1430Z, zone)
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T14:30:00.250Z"), instant1430Z.addingTimeInterval(0.25), zone)
                // The other designator forms Android and the web accept.
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T14:30Z"), instant1430Z, zone)
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T16:30:00+0200"), instant1430Z, zone)
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T16:30:00+02"), instant1430Z, zone)
                XCTAssertEqual(DateHelper.parseDate(from: "2024-07-16T14:30:00z"), instant1430Z, zone)
            }
        }
    }

    func testParseRefusesTrailingTextInsteadOfDroppingTheZone() throws {
        // The format styles stop reading early; without a shape check these parsed
        // as wall-clock 14:30 with the designator thrown away.
        inZone("Asia/Tokyo") {
            for text in ["2024-07-16T14:30:00,5Z", "2024-07-16T14:30:00 junk", "2024-07-16T14:30:00Zjunk",
                         "2024-07-16T14:30:00+02:00junk", "2024-07-16T14:30:00GMT", "2024-07-16T14:30:00+2"] {
                XCTAssertNil(DateHelper.parseDate(from: text), text)
            }
            XCTAssertNotNil(DateHelper.parseDate(from: "2024-07-16T09:05:00\n"), "a trailing newline is trimmed")
        }
    }

    func testParseOffsetLessDateTimeIsLocalWallClock() throws {
        try inZone("Asia/Tokyo") {
            let parts = try XCTUnwrap(localComponents(DateHelper.parseDate(from: "2024-07-16T09:05:00")))
            XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2024, 7, 16, 9, 5])
            // Seconds are optional, as on Android and the web.
            let short = try XCTUnwrap(localComponents(DateHelper.parseDate(from: "2024-07-16T09:05")))
            XCTAssertEqual([short.hour, short.minute, short.second], [9, 5, 0])
        }
    }

    func testParseDateOnlyIsLocalNoonOfThatDay() throws {
        for zone in ["America/Los_Angeles", "Pacific/Kiritimati"] {
            try inZone(zone) {
                let parts = try XCTUnwrap(localComponents(DateHelper.parseDate(from: "2024-07-16")))
                XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour], [2024, 7, 16, 12], zone)
                XCTAssertNotNil(DateHelper.parseDate(from: " 2024-07-16 "), "surrounding whitespace is trimmed")
            }
        }
    }

    func testFormatDateWritesTheLocalDay() throws {
        // Late evening and just after midnight: a UTC day would differ from the local
        // day in one of the two, in any zone but UTC.
        for zone in ["America/Los_Angeles", "Pacific/Kiritimati", "Asia/Tokyo"] {
            inZone(zone) {
                for hour in [0, 21] {
                    var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 16; c.hour = hour; c.minute = 30
                    let date = Calendar.current.date(from: c)!
                    XCTAssertEqual(DateHelper.formatDate(from: date), "2026-10-16", "\(zone) \(hour):30")
                }
            }
        }
    }

    func testZonedValueInDateOnlyModeShowsTheLocalDayOfTheInstant() throws {
        // UTC midnight on July 16 is the evening of July 15 in Los Angeles.
        inZone("America/Los_Angeles") {
            let parsed = DateHelper.parseDate(from: "2024-07-16T00:00:00Z")
            XCTAssertEqual(parsed.map(DateHelper.formatDate(from:)), "2024-07-15")
        }
        inZone("Europe/Warsaw") {
            let parsed = DateHelper.parseDate(from: "2024-07-16T00:00:00Z")
            XCTAssertEqual(parsed.map(DateHelper.formatDate(from:)), "2024-07-16")
        }
    }

    func testDateOnlyPickerEmitsTheLocalDay() throws {
        try inZone("America/Los_Angeles") {
            let elementDict: [String: Any] = ["id": 1, "type": "DatePicker", "properties": ["title": "Day"]]
            _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
            var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 16; c.hour = 21; c.minute = 30
            ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: Calendar.current.date(from: c)!)
            XCTAssertEqual(ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1), "2026-10-16")
        }
    }

    func testTimeBearingPickerRoundTripsAZonedValueAsLocalTime() throws {
        try inZone("Asia/Tokyo") {
            let elementDict: [String: Any] = ["id": 1, "type": "DatePicker",
                                              "properties": ["title": "When", "displayedComponents": "dateAndTime"]]
            _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
            ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "2024-07-16T14:30:00Z")
            // 14:30 UTC is 23:30 in Tokyo; the emitted form is offset-less local time.
            XCTAssertEqual(ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1), "2024-07-16T23:30:00")
            // An offset-less value round-trips unchanged.
            ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "2024-07-16T18:00:00")
            XCTAssertEqual(ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1), "2024-07-16T18:00:00")
        }
    }

    func testBuildViewAndApplyModifiersMissingProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "DatePicker",
            "properties": [:]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = DatePicker.buildView(element, viewModel, windowUUID, properties, logger)
        _ = DatePicker.applyModifiers(view, element, windowUUID, properties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.DatePicker) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}
