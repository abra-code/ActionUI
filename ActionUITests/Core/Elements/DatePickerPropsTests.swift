// Core/Elements/DatePickerPropsTests.swift
/*
 Tests for DatePicker.Props: the title default, the display style and component names, the
 range (needs "start" and "end" strings), the initial date as written and the action. The
 "stepperField" and "field" styles are dropped by validation off macOS but kept by Props, where the
 renderer shows the default style for them.
*/

import XCTest
@testable import ActionUI

final class DatePickerPropsTests: XCTestCase {

    func testDefaults() {
        let props = DatePicker.Props([:])
        XCTAssertEqual(props.title, "Date")
        XCTAssertNil(props.displayStyle)
        XCTAssertNil(props.displayedComponents)
        XCTAssertNil(props.range)
        XCTAssertEqual(props.selectedDate, "")
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = DatePicker.Props([
            "title": "When", "displayStyle": "graphical", "displayedComponents": "dateAndTime",
            "range": ["start": "2023-01-01", "end": "2025-12-31"], "selectedDate": "2024-07-16",
            "valueChangeActionID": "changed",
        ])
        XCTAssertEqual(props.title, "When")
        XCTAssertEqual(props.displayStyle, .graphical)
        XCTAssertEqual(props.displayedComponents, .dateAndTime)
        XCTAssertEqual(props.range, .init(start: "2023-01-01", end: "2025-12-31"))
        XCTAssertEqual(props.selectedDate, "2024-07-16")
        XCTAssertEqual(props.valueChangeActionID, "changed")
    }

    func testDisplayStyleNames() {
        for name in ["automatic", "compact", "graphical", "stepperField", "field"] {
            XCTAssertEqual(DatePicker.Props(["displayStyle": name]).displayStyle?.rawValue, name)
        }
        XCTAssertNil(DatePicker.Props(["displayStyle": "wheel"]).displayStyle)
        XCTAssertNil(DatePicker.Props(["displayStyle": 5]).displayStyle)
    }

    func testDisplayedComponentsNames() {
        XCTAssertEqual(DatePicker.Props(["displayedComponents": "date"]).displayedComponents, .date)
        XCTAssertEqual(DatePicker.Props(["displayedComponents": "hourAndMinute"]).displayedComponents, .hourAndMinute)
        XCTAssertNil(DatePicker.Props(["displayedComponents": "time"]).displayedComponents)
        XCTAssertNil(DatePicker.Props(["displayedComponents": 5]).displayedComponents)
    }

    func testRangeNeedsBothEnds() {
        XCTAssertNil(DatePicker.Props(["range": ["start": "2023-01-01"]]).range)
        XCTAssertNil(DatePicker.Props(["range": ["end": "2023-01-01"]]).range)
        XCTAssertNil(DatePicker.Props(["range": [String: String]()]).range)
    }

    func testRangeMustBeADictionaryOfStrings() {
        XCTAssertNil(DatePicker.Props(["range": ["start": 1, "end": 2]]).range)
        XCTAssertNil(DatePicker.Props(["range": "x"]).range)
        XCTAssertNil(DatePicker.Props(["range": ["start": "2023-01-01", "end": 2]]).range)
    }

    func testRangeIsKeptAsWritten() {
        // The renderer parses the dates and ignores a range that is not in order.
        let props = DatePicker.Props(["range": ["start": "not a date", "end": "2020-01-01"]])
        XCTAssertEqual(props.range, .init(start: "not a date", end: "2020-01-01"))
    }

    func testWrongTypesFallBack() {
        let props = DatePicker.Props(["title": 5, "selectedDate": 5, "valueChangeActionID": 5])
        XCTAssertEqual(props.title, "Date")
        XCTAssertEqual(props.selectedDate, "")
        XCTAssertNil(props.valueChangeActionID)
    }
}
