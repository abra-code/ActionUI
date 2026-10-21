// Tests/Common/JavaScriptLiteralTests.swift
/*
 The WebKit adapter writes every value it puts into a script as ActionUIJSON text
 (ActionUIWebKitJS.jsLiteral). These tests check, in JavaScriptCore, the property that relies on:
 that text is a JavaScript expression with the same value, whatever the string holds, so no value
 can end a literal early or inject code.
*/

import Foundation
import JavaScriptCore
import XCTest
@testable import ActionUI

final class JavaScriptLiteralTests: XCTestCase {
    private let context = JSContext()!

    // The value of `literal` as JavaScript reads it, written back as JSON by JavaScript itself.
    private func javaScriptReads(_ literal: String) -> String? {
        context.evaluateScript("JSON.stringify({result: \(literal)}.result)")?.toString()
    }

    func testStringsStayStrings() throws {
        let strings = [
            "it's", "say \"hi\"", "back\\slash", "a/b", "</script>", "line\nbreak", "tab\t", "\u{1}\u{1F}",
            "\u{2028}\u{2029}", "caf\u{E9} \u{1F600}", "'); alert(1); ('", "\"}); alert(1); ({\"", "",
        ]
        for string in strings {
            let literal = try ActionUIJSON.string(from: string)
            let read = try XCTUnwrap(javaScriptReads(literal), "Not a JavaScript expression: \(literal)")
            XCTAssertEqual(try ActionUIJSON.value(from: read) as? String, string, literal)
        }
        XCTAssertNil(context.exception, "No literal raised an exception")
    }

    func testNumbersBooleansNullAndContainers() throws {
        let cases: [(Any, String)] = [
            (true, "true"), (false, "false"), (5, "5"), (0.25, "0.25"), (-3, "-3"),
            (ActionUIJSONNull(), "null"),
            (["a", "it's"], #"["a","it's"]"#),
            (["k": [1, true, ActionUIJSONNull()] as [Any]] as [String: Any], #"{"k":[1,true,null]}"#),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(javaScriptReads(try ActionUIJSON.string(from: value)), expected)
        }
    }

    func testAnActionArgumentObjectIsOneExpression() throws {
        let args: [String: Any] = ["actionID": "it's.done", "windowUUID": "w", "viewID": 3, "viewPartID": 0, "context": "a'b"]
        let literal = try ActionUIJSON.string(from: args)
        let actionID = context.evaluateScript("(\(literal)).actionID")?.toString()
        XCTAssertEqual(actionID, "it's.done")
        XCTAssertEqual(context.evaluateScript("(\(literal)).viewID")?.toInt32(), 3)
    }
}
