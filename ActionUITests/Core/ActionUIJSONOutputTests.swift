// Core/ActionUIJSONOutputTests.swift
/*
 Exact-output tests for the JSON text ActionUI hands to hosts: ActionUIJSON.string(from:), the
 round trip through ActionUIJSON.value(from:), and the paths the C adapter, the remote server and
 the bindings take through the model (a value or state set from JSON text and read back as JSON
 text, as a string, and as the type a renderer reads).

 They pin what the JSONSerialization-based code writes, so replacing it shows every text that
 changes. Objects with more than one key are compared after parsing, since key order is not fixed.
*/

import Foundation
import XCTest
@testable import ActionUI

@MainActor
final class ActionUIJSONOutputTests: XCTestCase {
    private let model = ActionUIModel.shared
    private var windowUUID = ""

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        let description: [String: Any] = [
            "id": 100, "type": "VStack",
            "children": [
                ["id": 1, "type": "Slider", "properties": [:]],
                ["id": 2, "type": "Toggle", "properties": ["title": "On"]],
                ["id": 3, "type": "TabView", "children": []],
                ["id": 4, "type": "TextField", "properties": [:]],
                ["id": 5, "type": "ProgressView", "properties": [:]],
                ["id": 6, "type": "Text", "properties": ["text": "states"]],
            ],
        ]
        _ = try model.loadDescription(from: description, windowUUID: windowUUID)
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        try await super.tearDown()
    }

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
            "mixed array": [true, 1, 1.5, "x", NSNull()] as [Any],
            "inexact in array": [0.1, 1e-7, 2.0] as [Any],
            "slash in array": ["a/b"],
            "nested": [[1, [2]], [] as [Any]] as [Any],
            "one-key object": ["k": ["a": 1]],
            "empty object": [String: Any](),
            "rows": [["a", "b"], ["c"]],
        ]
        check([
            ("mixed array", "[true,1,1.5,\"x\",null]"),
            ("inexact in array", "[0.10000000000000001,9.9999999999999995e-08,2]"),
            ("slash in array", #"["a\/b"]"#),
            ("nested", "[[1,[2]],[]]"),
            ("one-key object", #"{"k":{"a":1}}"#),
            ("empty object", "{}"),
            ("rows", #"[["a","b"],["c"]]"#),
        ]) { text(values[$0]!) }
    }

    func testObjectWithSeveralKeys() throws {
        let object: [String: Any] = ["b": true, "a": 0.1, "c": ["x": NSNull()], "d": "\u{E9}/"]
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text(object).utf8)) as? NSDictionary)
        XCTAssertEqual(parsed, ["b": true, "a": 0.1, "c": ["x": NSNull()], "d": "\u{E9}/"] as NSDictionary)
    }

    func testValuesWithoutJSONThrow() {
        check([
            ("null", "throws: Cannot convert value of type NSNull to JSON"),
            ("date", "throws: Cannot convert value of type Date to JSON"),
            ("nan", "nan"),
        ]) { name in
            switch name {
            case "null": return text(NSNull())
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
            ("null", "throws: Cannot convert value of type NSNull to JSON"),
            ("[1,true,1.5,null]", "[1,true,1.5,null]"),
            (#"{"a":[0.1]}"#, #"{"a":[0.10000000000000001]}"#),
            ("[2.0,1e-7]", "[2,9.9999999999999995e-08]"),
        ], roundTrip)
    }

    // MARK: - Element values, as the C adapter and the remote server set and read them

    // JSON text as an adapter hands it to the model: parsed, then made Swift-native.
    private func parsedLikeAnAdapter(_ json: String) throws -> Any {
        FoundationBridge.native(try ActionUIJSON.value(from: json))
    }

    private func setValue(_ viewID: Int, json: String) throws {
        model.setElementValue(windowUUID: windowUUID, viewID: viewID, value: try parsedLikeAnAdapter(json))
    }

    private func valueText(_ viewID: Int) -> String {
        model.getElementValue(windowUUID: windowUUID, viewID: viewID).map({ text(FoundationBridge.foundation($0)) }) ?? "nil"
    }

    private func valueString(_ viewID: Int) -> String {
        model.getElementValueAsString(windowUUID: windowUUID, viewID: viewID) ?? "nil"
    }

    func testSliderValueFromJSON() throws {
        var results: [String] = []
        for json in ["5", "0.1", "2.5", "1e-7"] {
            try setValue(1, json: json)
            let typed = model.getElementValue(windowUUID: windowUUID, viewID: 1) as? Double
            results.append("\(json): \(valueText(1)) | \(valueString(1)) | \(typed.map { String($0) } ?? "not a Double")")
        }
        XCTAssertEqual(results, [
            "5: 5 | 5.0 | 5.0",
            "0.1: 0.1 | 0.1 | 0.1",
            "2.5: 2.5 | 2.5 | 2.5",
            "1e-7: 1e-07 | 1e-07 | 1e-07",
        ])
    }

    func testToggleValueFromJSON() throws {
        var results: [String] = []
        for json in ["true", "false"] {
            try setValue(2, json: json)
            let typed = model.getElementValue(windowUUID: windowUUID, viewID: 2) as? Bool
            results.append("\(json): \(valueText(2)) | \(valueString(2)) | \(typed.map { String($0) } ?? "not a Bool")")
        }
        XCTAssertEqual(results, ["true: true | true | true", "false: false | false | false"])
    }

    func testTabViewValueFromJSON() throws {
        var results: [String] = []
        for json in ["2", "2.0"] {
            try setValue(3, json: json)
            let typed = model.getElementValue(windowUUID: windowUUID, viewID: 3) as? Int
            results.append("\(json): \(valueText(3)) | \(valueString(3)) | \(typed.map { String($0) } ?? "not an Int")")
        }
        XCTAssertEqual(results, ["2: 2 | 2 | 2", "2.0: 2 | 2 | 2"])
    }

    func testTextFieldValueFromJSON() throws {
        try setValue(4, json: #""a/b é""#)
        XCTAssertEqual(valueText(4), "\"a\\/b \u{E9}\"")
        XCTAssertEqual(valueString(4), "a/b \u{E9}")
    }

    func testProgressViewValueFromJSON() throws {
        var results: [String] = []
        for json in ["0.25", "1"] {
            try setValue(5, json: json)
            let typed = model.getElementValue(windowUUID: windowUUID, viewID: 5) as? Double
            results.append("\(json): \(valueText(5)) | \(valueString(5)) | \(typed.map { String($0) } ?? "not a Double")")
        }
        XCTAssertEqual(results, ["0.25: 0.25 | 0.25 | 0.25", "1: 1 | 1.0 | 1.0"])
    }

    // MARK: - States

    private func stateText(_ key: String) -> String {
        model.getElementState(windowUUID: windowUUID, viewID: 6, key: key).map({ text(FoundationBridge.foundation($0)) }) ?? "nil"
    }

    private func stateString(_ key: String) -> String {
        model.getElementStateAsString(windowUUID: windowUUID, viewID: 6, key: key) ?? "nil"
    }

    func testStatesInferredFromStrings() {
        let inputs = ["true", "3", "1.5", "0.1", "plain", #"[1,true,"a/b"]"#, #"{"k":2}"#, "null"]
        var results: [String] = []
        for (index, input) in inputs.enumerated() {
            let key = "k\(index)"
            model.setElementStateFromString(windowUUID: windowUUID, viewID: 6, key: key, value: input)
            let state = model.getElementState(windowUUID: windowUUID, viewID: 6, key: key)
            results.append("\(input): \(stateText(key)) | \(stateString(key)) | \(state.map { "\(type(of: $0))" } ?? "nil")")
        }
        XCTAssertEqual(results, [
            "true: true | true | Bool",
            "3: 3 | 3 | Int",
            "1.5: 1.5 | 1.5 | Double",
            "0.1: 0.1 | 0.1 | Double",
            "plain: \"plain\" | plain | String",
            "[1,true,\"a/b\"]: [1,true,\"a\\/b\"] | (\n    1,\n    1,\n    \"a/b\"\n) | __NSArrayI",
            "{\"k\":2}: {\"k\":2} | {\n    k = 2;\n} | __NSSingleEntryDictionaryI",
            "null: throws: Cannot convert value of type NSNull to JSON | <null> | NSNull",
        ])
    }

    func testStatesSetFromJSON() throws {
        let inputs = ["true", "3", "2.5", #""s""#, "[1,2]"]
        var results: [String] = []
        for (index, input) in inputs.enumerated() {
            let key = "j\(index)"
            model.setElementState(windowUUID: windowUUID, viewID: 6, key: key, value: try parsedLikeAnAdapter(input))
            let state = model.getElementState(windowUUID: windowUUID, viewID: 6, key: key)
            results.append("\(input): \(stateText(key)) | \(stateString(key)) | \(state.map { "\(type(of: $0))" } ?? "nil")")
        }
        XCTAssertEqual(results, [
            "true: true | true | Bool",
            "3: 3 | 3 | Int",
            "2.5: 2.5 | 2.5 | Double",
            "\"s\": \"s\" | s | String",
            "[1,2]: [1,2] | [1, 2] | Array<Any>",
        ])
    }
}
