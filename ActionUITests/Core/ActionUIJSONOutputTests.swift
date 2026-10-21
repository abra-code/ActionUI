// Core/ActionUIJSONOutputTests.swift
/*
 Exact-output tests for the JSON text ActionUI hands to hosts: ActionUIJSON.string(from:) and the
 round trip through ActionUIJSON.value(from:). The same text through the model (a value or state
 set from JSON and read back) is pinned in Common/ActionUIJSONModelOutputTests.swift.

 They pinned what the JSONSerialization-based code wrote, so the move to JSONValue showed every
 text that changed. Objects with more than one key are compared after parsing, since key order
 is not fixed.
*/

import XCTest
@testable import ActionUI

final class ActionUIJSONOutputTests: XCTestCase {

    // Compares every case and reports all mismatches at once, as `input => actual`.
    private func check(_ cases: [(String, String)], _ actual: (String) -> String, file: StaticString = #filePath, line: UInt = #line) {
        let mismatches = cases.compactMap { input, expected -> String? in
            let got = actual(input)
            return got == expected ? nil : "\(input) => \(got)"
        }
        XCTAssertEqual(mismatches, [], file: file, line: line)
    }

    private func text(_ value: Any) -> String {
        do {
            return try ActionUIJSON.string(from: value)
        } catch {
            return "throws: \(error)"
        }
    }

    private func roundTrip(_ json: String) -> String {
        do {
            return text(try ActionUIJSON.value(from: json))
        } catch {
            return "throws: \(error)"
        }
    }

    // MARK: - string(from:) on Swift values

    func testScalarsFromSwiftValues() {
        let values: [String: Any] = [
            "true": true, "false": false, "0": 0, "-7": -7, "Int.max": Int.max,
            "1.5": 1.5, "2.0": 2.0, "0.1": 0.1, "1e-7": 1e-7, "1e21": 1e21, "-0.0": -0.0,
            "Float 0.5": Float(0.5),
        ]
        check([
            ("true", "true"), ("false", "false"), ("0", "0"), ("-7", "-7"), ("Int.max", "9223372036854775807"),
            ("1.5", "1.5"), ("2.0", "2"), ("0.1", "0.1"), ("1e-7", "1e-07"), ("1e21", "1e+21"), ("-0.0", "-0"),
            ("Float 0.5", "0.5"),
        ]) { text(values[$0]!) }
    }

    func testStringsFromSwiftValues() {
        let values: [String: String] = [
            "slash": "a/b", "quote": "say \"hi\"", "backslash": "a\\b", "newline": "a\nb", "tab": "a\tb",
            "control": "a\u{1}b", "delete": "a\u{7F}b", "accent": "caf\u{E9}", "emoji": "\u{1F600}", "empty": "",
            "separator": "a\u{2028}b",
        ]
        check([
            ("slash", #""a\/b""#), ("quote", #""say \"hi\"""#), ("backslash", #""a\\b""#), ("newline", #""a\nb""#),
            ("tab", #""a\tb""#), ("control", #""a\u0001b""#), ("delete", "\"a\u{7F}b\""), ("accent", "\"caf\u{E9}\""),
            ("emoji", "\"\u{1F600}\""), ("empty", #""""#), ("separator", "\"a\u{2028}b\""),
        ]) { text(values[$0]!) }
    }

    func testContainersFromSwiftValues() {
        let values: [String: Any] = [
            "mixed array": [true, 1, 1.5, "x", ActionUIJSONNull()] as [Any],
            "inexact in array": [0.1, 1e-7, 2.0] as [Any],
            "slash in array": ["a/b"],
            "nested": [[1, [2]], [] as [Any]] as [Any],
            "one-key object": ["k": ["a": 1]],
            "empty object": [String: Any](),
            "rows": [["a", "b"], ["c"]],
        ]
        check([
            ("mixed array", "[true,1,1.5,\"x\",null]"),
            ("inexact in array", "[0.1,1e-07,2]"),
            ("slash in array", #"["a\/b"]"#),
            ("nested", "[[1,[2]],[]]"),
            ("one-key object", #"{"k":{"a":1}}"#),
            ("empty object", "{}"),
            ("rows", #"[["a","b"],["c"]]"#),
        ]) { text(values[$0]!) }
    }

    func testObjectWithSeveralKeys() throws {
        let object: [String: Any] = ["b": true, "a": 0.1, "c": ["x": ActionUIJSONNull()], "d": "\u{E9}/"]
        let parsed = try JSONValue(parsing: Data(text(object).utf8))
        XCTAssertEqual(parsed, .object(["b": .bool(true), "a": .double(0.1), "c": .object(["x": .null]), "d": .string("\u{E9}/")]))
    }

    func testValuesWithoutJSONThrow() {
        check([
            ("null", "null"),
            ("date", "throws: Cannot convert value of type Date to JSON"),
            ("nan", "throws: Cannot convert nan to JSON: JSON has no non-finite numbers"),
        ]) { name in
            switch name {
            case "null": return text(ActionUIJSONNull())
            case "date": return text(Date(timeIntervalSince1970: 0))
            default: return text(Double.nan)
            }
        }
    }

    // MARK: - value(from:) then string(from:)

    func testRoundTripOfJSONText() {
        check([
            ("true", "true"), ("false", "false"), ("0", "0"), ("42", "42"), ("-7", "-7"),
            ("1.5", "1.5"), ("2.0", "2"), ("0.1", "0.1"), ("1e-7", "1e-07"), ("1e21", "1e+21"), ("-0.0", "-0"),
            ("9007199254740993", "9007199254740993"),
            (#""a/b""#, #""a\/b""#), (#""a\/b""#, #""a\/b""#), (#""é""#, "\"\u{E9}\""), (#""\u0001""#, #""\u0001""#),
            ("null", "null"),
            ("[1,true,1.5,null]", "[1,true,1.5,null]"),
            (#"{"a":[0.1]}"#, #"{"a":[0.1]}"#),
            ("[2.0,1e-7]", "[2,1e-07]"),
        ], roundTrip)
    }
}
