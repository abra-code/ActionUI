// Tests/Common/ActionUIJSONTests.swift
/*
 ActionUIJSONTests.swift

 Pins the behavior of ActionUIJSON, the JSON conversion shared by the language adapters.
 The C adapter, the remote binding, and the in-process Python and Node modules all depend on
 this encoding being stable: a change here is a wire-format change for every one of them.
*/

import XCTest
import SwiftUI
@testable import ActionUI

final class ActionUIJSONTests: XCTestCase {

    // MARK: - string(from:)

    func testStringScalarIsQuotedAndEscaped() throws {
        XCTAssertEqual(try ActionUIJSON.string(from: "hello"), "\"hello\"")
        XCTAssertEqual(try ActionUIJSON.string(from: "say \"hi\"\n"), "\"say \\\"hi\\\"\\n\"")
        XCTAssertEqual(try ActionUIJSON.string(from: ""), "\"\"")
    }

    func testNumberScalars() throws {
        XCTAssertEqual(try ActionUIJSON.string(from: 42), "42")
        XCTAssertEqual(try ActionUIJSON.string(from: -7), "-7")
        XCTAssertEqual(try ActionUIJSON.string(from: 3.5), "3.5")
        XCTAssertEqual(try ActionUIJSON.string(from: NSNumber(value: 12)), "12")
    }

    func testBoolScalarsIncludingBridgedCFBoolean() throws {
        XCTAssertEqual(try ActionUIJSON.string(from: true), "true")
        XCTAssertEqual(try ActionUIJSON.string(from: false), "false")
        // A Bool that arrived through Foundation bridging is an NSNumber backed by CFBoolean.
        let bridged: Any = NSNumber(value: true)
        XCTAssertEqual(try ActionUIJSON.string(from: bridged), "true")
        XCTAssertEqual(try ActionUIJSON.string(from: kCFBooleanFalse as Any), "false")
    }

    func testStringArray() throws {
        XCTAssertEqual(try ActionUIJSON.string(from: ["a", "b"]), "[\"a\",\"b\"]")
        XCTAssertEqual(try ActionUIJSON.string(from: [String]()), "[]")
    }

    func testRowsArray() throws {
        let rows: [[String]] = [["Alice", "30"], ["Bob", "25"]]
        XCTAssertEqual(try ActionUIJSON.string(from: rows), "[[\"Alice\",\"30\"],[\"Bob\",\"25\"]]")
    }

    func testNestedObjectRoundTrips() throws {
        let object: [String: Any] = ["name": "x", "count": 2, "flags": [true, false], "inner": ["k": "v"]]
        let text = try ActionUIJSON.string(from: object)
        let back = try XCTUnwrap(try ActionUIJSON.value(from: text) as? [String: Any])
        XCTAssertEqual(back["name"] as? String, "x")
        XCTAssertEqual(back["count"] as? Int, 2)
        XCTAssertEqual(back["flags"] as? [Bool], [true, false])
        XCTAssertEqual((back["inner"] as? [String: Any])?["k"] as? String, "v")
    }

    func testUnsupportedTypeThrowsWithTypeName() {
        XCTAssertThrowsError(try ActionUIJSON.string(from: Date())) { error in
            let message = (error as? ActionUIJSONError)?.message ?? ""
            XCTAssertEqual(message, "Cannot convert value of type Date to JSON")
        }
    }

    // MARK: - value(from:)

    func testValueParsesFragments() throws {
        XCTAssertEqual(try ActionUIJSON.value(from: "\"text\"") as? String, "text")
        XCTAssertEqual(try ActionUIJSON.value(from: "5") as? Int, 5)
        XCTAssertEqual(try ActionUIJSON.value(from: "2.5") as? Double, 2.5)
        XCTAssertEqual(try ActionUIJSON.value(from: "true") as? Bool, true)
        XCTAssertTrue(try ActionUIJSON.value(from: "null") is NSNull)
    }

    func testValueParsesContainers() throws {
        XCTAssertEqual(try ActionUIJSON.value(from: "[\"a\",\"b\"]") as? [String], ["a", "b"])
        XCTAssertEqual(try ActionUIJSON.value(from: "[[\"1\",\"2\"]]") as? [[String]], [["1", "2"]])
        let dict = try XCTUnwrap(try ActionUIJSON.value(from: "{\"k\":1}") as? [String: Any])
        XCTAssertEqual(dict["k"] as? Int, 1)
    }

    func testInvalidJSONThrowsParseMessage() {
        XCTAssertThrowsError(try ActionUIJSON.value(from: "{not json")) { error in
            let message = (error as? ActionUIJSONError)?.message ?? ""
            XCTAssertTrue(message.hasPrefix("Failed to parse JSON: "), message)
        }
    }

    func testScalarStringRoundTrip() throws {
        let original = "line one\nline \"two\" \u{1F600}"
        let text = try ActionUIJSON.string(from: original)
        XCTAssertEqual(try ActionUIJSON.value(from: text) as? String, original)
    }

    // MARK: - dialogButtons(from:)

    func testDialogButtonsFromJSONString() throws {
        let json = """
        [{"title":"Cancel","role":"cancel"},
         {"title":"Delete","role":"destructive","actionID":"delete.confirmed"},
         {"title":"OK"}]
        """
        let buttons = try XCTUnwrap(ActionUIJSON.dialogButtons(from: json))
        XCTAssertEqual(buttons.count, 3)
        XCTAssertEqual(buttons[0].title, "Cancel")
        XCTAssertEqual(buttons[0].role, .cancel)
        XCTAssertNil(buttons[0].actionID)
        XCTAssertEqual(buttons[1].role, .destructive)
        XCTAssertEqual(buttons[1].actionID, "delete.confirmed")
        XCTAssertNil(buttons[2].role)
    }

    func testDialogButtonsFromDecodedArray() throws {
        let decoded: [[String: Any]] = [["title": "Go", "role": "default", "actionID": "go"]]
        let buttons = try XCTUnwrap(ActionUIJSON.dialogButtons(from: decoded))
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons[0].title, "Go")
        XCTAssertNil(buttons[0].role, "\"default\" maps to nil like an omitted role")
        XCTAssertEqual(buttons[0].actionID, "go")

        let anyArray: [Any] = [["title": "One"], ["title": "Two"]]
        XCTAssertEqual(ActionUIJSON.dialogButtons(from: anyArray)?.count, 2)
    }

    func testDialogButtonsRejectsEmptyMissingAndMalformed() {
        XCTAssertNil(ActionUIJSON.dialogButtons(from: nil))
        XCTAssertNil(ActionUIJSON.dialogButtons(from: "[]"))
        XCTAssertNil(ActionUIJSON.dialogButtons(from: "not json"))
        XCTAssertNil(ActionUIJSON.dialogButtons(from: "{\"title\":\"not an array\"}"))
        XCTAssertNil(ActionUIJSON.dialogButtons(from: 42))
        // Entries without a title are skipped; an array of only such entries yields an empty list.
        XCTAssertEqual(ActionUIJSON.dialogButtons(from: "[{\"role\":\"cancel\"}]")?.count, 0)
    }

    // MARK: - insertPosition(from:)

    func testInsertPositionDefaultsAndStrings() throws {
        assertPosition(try ActionUIJSON.insertPosition(from: nil), .append)
        assertPosition(try ActionUIJSON.insertPosition(from: NSNull()), .append)
        assertPosition(try ActionUIJSON.insertPosition(from: "append"), .append)
        assertPosition(try ActionUIJSON.insertPosition(from: "prepend"), .prepend)
    }

    func testInsertPositionObjectForms() throws {
        assertPosition(try ActionUIJSON.insertPosition(from: ["kind": "append"]), .append)
        assertPosition(try ActionUIJSON.insertPosition(from: ["kind": "prepend"]), .prepend)
        assertPosition(try ActionUIJSON.insertPosition(from: ["kind": "at", "index": 2]), .at(2))
        assertPosition(try ActionUIJSON.insertPosition(from: ["kind": "before", "siblingID": 20]), .before(siblingID: 20))
        assertPosition(try ActionUIJSON.insertPosition(from: ["kind": "after", "siblingID": 21]), .after(siblingID: 21))
        // Values decoded from JSON arrive as NSNumber.
        assertPosition(try ActionUIJSON.insertPosition(from: ["kind": "at", "index": NSNumber(value: 3)]), .at(3))
    }

    func testInsertPositionRejectsBadInput() throws {
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: ["kind": "sideways"]))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: ["kind": "at"]))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: ["kind": "at", "index": "2"]))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: ["kind": "before", "siblingID": true]))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: ["index": 2]))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: 7))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: "at"))

        // The forms the remote server actually sees: values decoded by JSONSerialization, where a
        // JSON bool is an NSNumber (CFBoolean) that `as? Int` would happily bridge to 1, and a
        // fractional number is an NSNumber that intValue would truncate.
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: try ActionUIJSON.value(from: "{\"kind\":\"at\",\"index\":true}")))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: try ActionUIJSON.value(from: "{\"kind\":\"before\",\"siblingID\":false}")))
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: try ActionUIJSON.value(from: "{\"kind\":\"at\",\"index\":2.7}")))
        assertPosition(try ActionUIJSON.insertPosition(from: try ActionUIJSON.value(from: "{\"kind\":\"at\",\"index\":2.0}")), .at(2))
        assertPosition(try ActionUIJSON.insertPosition(from: try ActionUIJSON.value(from: "{\"kind\":\"after\",\"siblingID\":21}")), .after(siblingID: 21))
    }

    // MARK: - modalStyle(from:)

    func testModalStyle() throws {
        XCTAssertEqual(try ActionUIJSON.modalStyle(from: nil), .sheet)
        XCTAssertEqual(try ActionUIJSON.modalStyle(from: "sheet"), .sheet)
        XCTAssertEqual(try ActionUIJSON.modalStyle(from: "fullScreenCover"), .fullScreenCover)
        XCTAssertThrowsError(try ActionUIJSON.modalStyle(from: "popover"))
    }
}

// InsertPosition is not Equatable in core, and adding a conformance here (even test-only) would
// become a duplicate-conformance build error the day core adds one. Compare a description instead.
private func describe(_ position: InsertPosition) -> String {
    switch position {
    case .append:                   return "append"
    case .prepend:                  return "prepend"
    case .at(let index):            return "at(\(index))"
    case .before(let siblingID):    return "before(\(siblingID))"
    case .after(let siblingID):     return "after(\(siblingID))"
    }
}

private func assertPosition(_ actual: InsertPosition, _ expected: InsertPosition, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(describe(actual), describe(expected), file: file, line: line)
}
