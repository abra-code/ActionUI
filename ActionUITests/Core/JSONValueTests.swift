// Core/JSONValueTests.swift
/*
 Tests for JSONValue and ActionUIJSONNull: parsing JSON text into the right kind (integral
 numbers as Int), writing it back, the Swift-native form, and which Swift values it accepts.
*/

import XCTest
@testable import ActionUI

final class JSONValueTests: XCTestCase {

    private func parse(_ text: String) throws -> JSONValue {
        try JSONValue(parsing: Data(text.utf8))
    }

    // MARK: - Parsing

    func testParsesEachKind() throws {
        let cases: [(String, JSONValue)] = [
            ("null", .null), ("true", .bool(true)), ("false", .bool(false)),
            ("0", .int(0)), ("-7", .int(-7)), ("9007199254740993", .int(9_007_199_254_740_993)),
            ("1.0", .int(1)), ("1e2", .int(100)),
            ("1.5", .double(1.5)), ("0.1", .double(0.1)), ("1e-7", .double(1e-7)), ("1e21", .double(1e21)),
            (#""a\/b""#, .string("a/b")), (#""é\n""#, .string("\u{E9}\n")), (#""""#, .string("")),
            ("[1,true,null,\"x\"]", .array([.int(1), .bool(true), .null, .string("x")])),
            (#"{"k":{"a":[]}}"#, .object(["k": .object(["a": .array([])])])),
            (" [ ] ", .array([])),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(try parse(text), expected, text)
        }
    }

    // Accepted as JSONSerialization accepts them: a trailing comma, a repeated key (the first wins).
    func testAcceptsWhatJSONSerializationAccepts() throws {
        XCTAssertEqual(try parse("[1,]"), .array([.int(1)]))
        XCTAssertEqual(try parse(#"{"k":1,}"#), .object(["k": .int(1)]))
        XCTAssertEqual(try parse(#"{"k":1,"k":2}"#), .object(["k": .int(1)]))
    }

    func testNegativeZeroKeepsItsSign() throws {
        guard case .double(let zero) = try parse("-0.0") else { return XCTFail("-0.0 is not a double") }
        XCTAssertEqual(zero.sign, .minus)
        // The decoder does not show the text, so "-0" is negative zero too (JSONSerialization gives 0).
        guard case .double(let alsoZero) = try parse("-0") else { return XCTFail("-0 is not a double") }
        XCTAssertEqual(alsoZero.sign, .minus)
        XCTAssertEqual(try parse("0.0"), .int(0))
    }

    func testRefusesTextThatIsNotJSON() {
        for text in ["", "{", "tru", "01", "1.", "[1]x", "{'k':1}", "NaN", "\"open"] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    // MARK: - Writing

    func testWritesTheShortestNumberText() throws {
        let cases: [(JSONValue, String)] = [
            (.int(0), "0"), (.int(Int.max), "9223372036854775807"), (.double(1.5), "1.5"),
            (.double(0.1), "0.1"), (.double(1e-7), "1e-07"), (.double(2.0), "2"),
            (.array([.double(0.1), .double(1e-7)]), "[0.1,1e-07]"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(try value.text(), expected)
        }
    }

    func testWritesStringsAndOptions() throws {
        XCTAssertEqual(try JSONValue.string("a/b").text(), #""a\/b""#)
        XCTAssertEqual(try JSONValue.string("a/b").text(escapingSlashes: false), #""a/b""#)
        XCTAssertEqual(try JSONValue.string("say \"hi\"\n\u{1}").text(), #""say \"hi\"\n\u0001""#)
        XCTAssertEqual(try JSONValue.null.text(), "null")
        XCTAssertEqual(try JSONValue.bool(false).text(), "false")
        let object = JSONValue.object(["b": .int(2), "a": .int(1), "c": .null])
        XCTAssertEqual(try object.text(sortedKeys: true), #"{"a":1,"b":2,"c":null}"#)
    }

    func testNonFiniteDoublesThrow() {
        XCTAssertThrowsError(try JSONValue.double(.nan).text())
        XCTAssertThrowsError(try JSONValue.double(.infinity).text())
    }

    func testRoundTrips() throws {
        for text in ["true", "42", "0.1", "1e-07", #""a\/b""#, "null", #"[1,[2.5,"x"],null]"#, #"{"a":{"b":false}}"#] {
            XCTAssertEqual(try parse(text).text(sortedKeys: true), text)
        }
    }

    // MARK: - Swift-native form

    func testAnyValueIsSwiftNative() throws {
        let value = try parse(#"[true,1,1.5,"s",null,{"k":[2]}]"#).anyValue
        let items = try XCTUnwrap(value as? [Any])
        XCTAssertTrue(type(of: items[0]) == Bool.self)
        XCTAssertTrue(type(of: items[1]) == Int.self)
        XCTAssertTrue(type(of: items[2]) == Double.self)
        XCTAssertTrue(type(of: items[3]) == String.self)
        XCTAssertTrue(items[4] is ActionUIJSONNull)
        let object = try XCTUnwrap(items[5] as? [String: Any])
        XCTAssertEqual(object["k"] as? [Int], [2])
    }

    func testFromSwiftValues() {
        XCTAssertEqual(JSONValue(any: true), .bool(true))
        XCTAssertEqual(JSONValue(any: 3), .int(3))
        XCTAssertEqual(JSONValue(any: 2.5), .double(2.5))
        XCTAssertEqual(JSONValue(any: Float(0.5)), .double(0.5))
        XCTAssertEqual(JSONValue(any: "x"), .string("x"))
        XCTAssertEqual(JSONValue(any: ActionUIJSONNull()), .null)
        XCTAssertEqual(JSONValue(any: [["a", "b"]]), .array([.array([.string("a"), .string("b")])]))
        XCTAssertEqual(JSONValue(any: ["k": [1, 2]] as [String: Any]), .object(["k": .array([.int(1), .int(2)])]))
        XCTAssertEqual(JSONValue(any: [Any]()), .array([]))
    }

    // Today's JSONSerialization path serialized these through NSNumber bridging; Core has no
    // bridge, so JSONValue takes them directly.
    func testFromOtherNumberTypesAndOptionals() {
        XCTAssertEqual(JSONValue(any: Int64(5)), .int(5))
        XCTAssertEqual(JSONValue(any: Int32(-3)), .int(-3))
        XCTAssertEqual(JSONValue(any: UInt8(200)), .int(200))
        XCTAssertEqual(JSONValue(any: UInt.max), .double(Double(UInt.max)), "Beyond Int's range")
        XCTAssertEqual(JSONValue(any: Float(0.5)), .double(0.5))
        XCTAssertEqual(JSONValue(any: Optional(5) as Any), .int(5))
        XCTAssertEqual(JSONValue(any: Optional<Int>.none as Any), .null)
        XCTAssertEqual(JSONValue(any: Optional(true) as Any), .bool(true))
        XCTAssertEqual(JSONValue(any: Optional("s") as Any), .string("s"))
        XCTAssertEqual(JSONValue(any: [1, nil] as [Int?]), .array([.int(1), .null]))
        XCTAssertNil(JSONValue(any: Optional(Date()) as Any), "A wrapped value without JSON is still refused")
    }

    func testRefusesValuesWithoutJSON() {
        XCTAssertNil(JSONValue(any: Date()))
        XCTAssertNil(JSONValue(any: [1, Date()] as [Any]), "One value without JSON refuses the array")
        XCTAssertNil(JSONValue(any: ["k": Date()] as [String: Any]))
        XCTAssertNil(JSONValue(any: [1: "x"]), "Keys must be strings")
    }

    func testFromSwiftValuesBackToAnyValueKeepsTheValue() throws {
        let original: [String: Any] = ["a": [true, 1, 0.1, ActionUIJSONNull()] as [Any], "b": "x"]
        let back = try XCTUnwrap(JSONValue(any: original)?.anyValue as? [String: Any])
        XCTAssertEqual(JSONValue(any: back), JSONValue(any: original))
    }
}
