// Core/ActionUIJSONModelOutputTests.swift
/*
 Exact-output tests for the paths the C adapter, the remote server and the bindings take through
 the model: a value or state set from JSON text and read back as JSON text, as a string, and as
 the type a renderer reads. The text of ActionUIJSON alone is pinned in
 Core/ActionUIJSONOutputTests.swift.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ActionUIJSONModelOutputTests: XCTestCase {
    private let model = ActionUIModel.shared
    private var windowUUID = ""

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
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
    }

    private func text(_ value: Any) -> String {
        do {
            return try ActionUIJSON.string(from: value)
        } catch {
            return "throws: \(error)"
        }
    }

    // MARK: - Element values, as the C adapter and the remote server set and read them

    // JSON text as an adapter hands it to the model: parsed into Swift-native values.
    private func parsedLikeAnAdapter(_ json: String) throws -> Any {
        try ActionUIJSON.value(from: json)
    }

    private func setValue(_ viewID: Int, json: String) throws {
        model.setElementValue(windowUUID: windowUUID, viewID: viewID, value: try parsedLikeAnAdapter(json))
    }

    private func valueText(_ viewID: Int) -> String {
        model.getElementValue(windowUUID: windowUUID, viewID: viewID).map(text) ?? "nil"
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
        model.getElementState(windowUUID: windowUUID, viewID: 6, key: key).map(text) ?? "nil"
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
            "[1,true,\"a/b\"]: [1,true,\"a\\/b\"] | [1, true, \"a/b\"] | Array<Any>",
            "{\"k\":2}: {\"k\":2} | [\"k\": 2] | Dictionary<String, Any>",
            "null: null | <null> | ActionUIJSONNull",
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
