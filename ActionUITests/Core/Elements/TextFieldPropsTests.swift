// Core/Elements/TextFieldPropsTests.swift
/*
 Tests for TextField.Props: the text and labels, the number format and its initial value, the axis,
 the line limit, the actions.
*/

import XCTest
@testable import ActionUI

final class TextFieldPropsTests: XCTestCase {

    func testDefaults() {
        let props = TextField.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.prompt)
        XCTAssertNil(props.text)
        XCTAssertNil(props.textContentType)
        XCTAssertNil(props.format)
        XCTAssertEqual(props.formattedInitialValue, "0")
        XCTAssertNil(props.axis)
        XCTAssertNil(props.lineLimit)
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.valueChangeActionID)
        XCTAssertEqual(props.initialValue, "")
    }

    func testTextValues() {
        let props = TextField.Props([
            "title": "Name", "prompt": "Enter", "text": "Hello", "textContentType": "username",
            "actionID": "submit", "valueChangeActionID": "changed",
        ])
        XCTAssertEqual(props.title, "Name")
        XCTAssertEqual(props.prompt, "Enter")
        XCTAssertEqual(props.text, "Hello")
        XCTAssertEqual(props.textContentType, "username")
        XCTAssertEqual(props.actionID, "submit")
        XCTAssertEqual(props.valueChangeActionID, "changed")
        XCTAssertEqual(props.initialValue, "Hello")
    }

    func testWrongTypesAreIgnored() {
        let props = TextField.Props(["title": 5, "prompt": 5, "text": 5, "textContentType": 5, "axis": 5])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.prompt)
        XCTAssertNil(props.text)
        XCTAssertNil(props.textContentType)
        XCTAssertNil(props.axis)
    }

    func testFormats() {
        XCTAssertEqual(TextField.Props(["format": "integer"]).format, .integer)
        XCTAssertEqual(TextField.Props(["format": "decimal", "fractionLength": 2]).format, .decimal(minFraction: 2, maxFraction: 2))
        XCTAssertEqual(
            TextField.Props(["format": "percent", "fractionLength": ["min": 0, "max": 1]]).format,
            .percent(minFraction: 0, maxFraction: 1)
        )
        XCTAssertEqual(
            TextField.Props(["format": "currency", "currencyCode": "EUR"]).format,
            .currency(code: "EUR", minFraction: nil, maxFraction: nil)
        )
        XCTAssertEqual(
            TextField.Props(["format": "currency", "currencyCode": 5]).format,
            .currency(code: "USD", minFraction: nil, maxFraction: nil)
        )
        XCTAssertNil(TextField.Props(["format": "money"]).format)
        XCTAssertNil(TextField.Props(["format": 5]).format)
    }

    func testFormattedInitialValue() {
        XCTAssertEqual(TextField.Props(["format": "decimal", "value": 9.99]).initialValue, "9.99")
        XCTAssertEqual(TextField.Props(["format": "integer", "value": 9]).initialValue, "9")
        XCTAssertEqual(TextField.Props(["format": "decimal", "value": "3.5"]).initialValue, "3.5")
        XCTAssertEqual(TextField.Props(["format": "integer", "value": true, "text": "7"]).initialValue, "7")
        XCTAssertEqual(TextField.Props(["format": "integer"]).initialValue, "0")
    }

    func testUnknownFormatIsAPlainField() {
        // The text, not "0": an unknown format is no format.
        XCTAssertEqual(TextField.Props(["format": "money", "value": 9.99]).initialValue, "")
        XCTAssertEqual(TextField.Props(["format": "money", "text": "Hello"]).initialValue, "Hello")
    }

    func testAxis() {
        XCTAssertEqual(TextField.Props(["axis": "vertical"]).axis, .vertical)
        XCTAssertEqual(TextField.Props(["axis": "horizontal"]).axis, .horizontal)
        XCTAssertNil(TextField.Props(["axis": "diagonal"]).axis)
    }

    func testLineLimit() {
        XCTAssertEqual(TextField.Props(["lineLimit": 3]).lineLimit, .exact(3))
        XCTAssertEqual(TextField.Props(["lineLimit": ["min": 3]]).lineLimit, .range(min: 3, max: nil))
        XCTAssertEqual(TextField.Props(["lineLimit": ["max": 5]]).lineLimit, .range(min: nil, max: 5))
        XCTAssertEqual(TextField.Props(["lineLimit": ["min": 3, "max": 10]]).lineLimit, .range(min: 3, max: 10))
        XCTAssertNil(TextField.Props(["lineLimit": [String: Any]()]).lineLimit)
        XCTAssertNil(TextField.Props(["lineLimit": ["min": "a"]]).lineLimit)
        XCTAssertNil(TextField.Props(["lineLimit": "3"]).lineLimit)
    }
}
