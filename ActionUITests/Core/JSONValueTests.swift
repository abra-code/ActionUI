// Core/JSONValueTests.swift
/*
 Tests for JSONValue and ActionUIJSONNull: parsing JSON text into the right kind (integral
 numbers as Int), writing it back, the Swift-native form, and which Swift values it accepts.
*/

import Foundation
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
        // "-0" is negative zero too, as JSONDecoder gave it (JSONSerialization gives 0).
        for text in ["-0", "-0e0", "-0.0e5", "-1e-400"] {
            guard case .double(let alsoZero) = try parse(text) else { return XCTFail("\(text) is not a double") }
            XCTAssertEqual(alsoZero.sign, .minus, text)
        }
        XCTAssertEqual(try parse("0.0"), .int(0))
        XCTAssertEqual(try parse("0e0"), .int(0))
    }

    func testRefusesTextThatIsNotJSON() {
        for text in ["", "{", "tru", "01", "1.", "[1]x", "{'k':1}", "NaN", "\"open"] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    // What JSONDecoder accepted, which documents and adapters may rely on.
    func testAcceptsWhatJSONDecoderAccepts() throws {
        let cases: [(String, JSONValue)] = [
            ("1E2", .int(100)), ("1e+2", .int(100)), ("1.0e0", .int(1)), ("100e-2", .int(1)), ("5e-1", .double(0.5)),
            ("9007199254740993.0", .int(9_007_199_254_740_993)), ("-9223372036854775808", .int(Int.min)),
            ("12345678901234567890", .double(1.2345678901234567e19)), ("-9223372036854775809", .double(-9.223372036854775808e18)),
            ("9007199254740993e0", .int(9_007_199_254_740_993)), ("90071992547409930e-1", .int(9_007_199_254_740_993)),
            ("9007199254740993.00000000001", .double(9.007199254740994e15)), ("-9223372036854775809e0", .double(-9.223372036854775808e18)),
            ("\"\u{FEFF}x\"", .string("\u{FEFF}x")), ("\"\u{FEFF}\u{E9}\"", .string("\u{FEFF}\u{E9}")), (#""﻿éé""#, .string("\u{FEFF}\u{E9}\u{E9}")),
            (#""\"\\\/\b\f\n\r\t""#, .string("\"\\/\u{8}\u{C}\n\r\t")),
            (#""Aé中\u0000""#, .string("A\u{E9}\u{4E2D}\u{0}")),
            (#""😀 😀""#, .string("\u{1F600} \u{1F600}")),
            ("\"\u{E9}\u{1F600}\u{7F}\u{2028}\"", .string("\u{E9}\u{1F600}\u{7F}\u{2028}")),
            (#"["éé"]"#, .array([.string("\u{E9}\u{E9}")])),
            (" \n\t\r[1]\n", .array([.int(1)])),
            (#"{ "a" : 1 , "b" : [ ] , "" : { } }"#, .object(["a": .int(1), "b": .array([]), "": .object([:])])),
            (#"{"a":[1,],}"#, .object(["a": .array([.int(1)])])),
            (#"{"a":null,"a":1}"#, .object(["a": .null])),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(try parse(text), expected, text)
        }
        // A UTF-8 byte order mark, and UTF-16 text (JSONDecoder reads it; it refuses UTF-32 with a mark).
        XCTAssertEqual(try JSONValue(parsing: Data([0xEF, 0xBB, 0xBF] + Array("[1]".utf8))), .array([.int(1)]))
        for encoding in [String.Encoding.utf16, .utf16BigEndian, .utf16LittleEndian] {
            let data = try XCTUnwrap(#"[1,"é"]"#.data(using: encoding))
            XCTAssertEqual(try JSONValue(parsing: data), .array([.int(1), .string("\u{E9}")]), "\(encoding)")
        }
    }

    func testRefusesWhatJSONDecoderRefuses() {
        let texts = [
            "[,]", "[1,,2]", "{,}", #"{"a":1,,}"#, "[1 2]", #"{"a" 1}"#, "{1:2}", "[1,]]", "[]]", "{}}",
            "+1", ".5", "-", "-01", "1.5e", "1e+", "[1.e5]", "1e400", "-1e400",
            "True", "nul", "nullx", "[tru]", "  ", "\u{A0}1", "[1]\u{0}",
            #""\x""#, #""\u12""#, #""\uZZZZ""#, #""\uD83D""#, #""\uD83Dx""#, #""\uD83DA""#, #""\uDE00""#,
            "\"a\u{1}b\"", "\"a\tb\"", "\"a\nb\"", "\"\u{0}\"",
        ]
        for text in texts {
            XCTAssertThrowsError(try parse(text), text.debugDescription)
        }
        // Bytes that are not UTF-8: a lone byte, a truncated sequence, an encoded surrogate.
        for bytes in [[0x22, 0xFF, 0x22], [0x22, 0xC3, 0x22], [0x22, 0xF0, 0x9F, 0x98, 0x22], [0x22, 0xED, 0xA0, 0x80, 0x22]] as [[UInt8]] {
            XCTAssertThrowsError(try JSONValue(parsing: Data(bytes)), "\(bytes)")
        }
    }

    func testRefusalNamesTheOffset() {
        XCTAssertThrowsError(try parse("[1,x]")) { error in
            XCTAssertEqual("\(error)", "Unexpected character at byte 3")
        }
        XCTAssertThrowsError(try parse("[\"open")) { error in
            XCTAssertEqual("\(error)", "Unterminated string at byte 1")
        }
    }

    // JSONDecoder's limit: 512 levels, empty innermost container included.
    func testNestingLimit() throws {
        func nested(_ depth: Int) -> String {
            String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        }
        var value = try parse(nested(512))
        var depth = 0
        while case .array(let items) = value {
            depth += 1
            value = items.first ?? .null
        }
        XCTAssertEqual(depth, 512)
        XCTAssertThrowsError(try parse(nested(513))) { error in
            XCTAssertEqual("\(error)", "Nested deeper than 512 levels at byte 512")
        }
        XCTAssertThrowsError(try parse(String(repeating: #"{"k":"#, count: 513) + "1" + String(repeating: "}", count: 513)))
    }

    // The parser does not recurse: the deepest text it accepts parses on a dispatch queue
    // thread's 512 KB stack, which JSONDecoder's recursion overflowed. (Releasing the tree still
    // recurses, needing about 256 KB at this depth in a debug build.)
    func testParsesTheDeepestTextOnASmallStack() {
        let text = String(repeating: #"{"k":["#, count: 256) + String(repeating: "]}", count: 256)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var parsed = false
        let thread = Thread {
            parsed = (try? JSONValue(parsing: Data(text.utf8))) != nil
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        done.wait()
        XCTAssertTrue(parsed)
    }

    // The parser against JSONDecoder, which it replaced, on generated documents: the same value
    // for each, numbers included (compared as written, so a Double's every bit counts).
    func testMatchesJSONDecoderOnGeneratedDocuments() throws {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random(_ range: ClosedRange<Int>) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return range.lowerBound + Int((state >> 33) % UInt64(range.count))
        }
        func document(_ depth: Int) -> String {
            switch random(0...(depth > 4 ? 4 : 7)) {
            case 0: return "\(random(-1000...1000))"
            case 1: return "\(Double(random(-1_000_000...1_000_000)) / Double(random(1...977)))"
            case 2: return #""s\n\#(random(0...9))éé\/""#
            case 3: return ["true", "false", "null"][random(0...2)]
            case 4: return "\(random(-3...3))e\(random(-3...20))"
            case 5, 6: return "[" + (0..<random(0...4)).map { _ in document(depth + 1) }.joined(separator: ",") + "]"
            default: return "{" + (0..<random(0...4)).map { _ in "\"k\(random(0...3))\" : " + document(depth + 1) }.joined(separator: ",") + "}"
            }
        }
        for _ in 0..<2000 {
            let data = Data(document(0).utf8)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            let parsed = try JSONValue(parsing: data)
            XCTAssertEqual(parsed, decoded)
            XCTAssertEqual(try parsed.text(sortedKeys: true), try encoded(decoded, sortedKeys: true))
        }
    }

    // JSONEncoder's text for a value, which JSONWriter replaced.
    private func encoded(_ value: JSONValue, sortedKeys: Bool = false, escapingSlashes: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if sortedKeys {
            formatting.insert(.sortedKeys)
        }
        if !escapingSlashes {
            formatting.insert(.withoutEscapingSlashes)
        }
        encoder.outputFormatting = formatting
        return String(decoding: try encoder.encode(value), as: UTF8.self)
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

    // The writer against JSONEncoder, which it replaced: numbers, every escape, key order.
    func testWritesWhatJSONEncoderWrote() throws {
        let doubles: [Double] = [
            0, -0.0, 1, 2, 1.5, -2.5, 0.1, 0.30000000000000004, 1e-7, 1e-5, 1e-4, 0.001, 4.35e-5, 5e-324,
            1e15, 1e16, 1e21, 1e300, 1.7976931348623157e308, 9007199254740992, 123456789012345680, Double(Int.max),
        ]
        for number in doubles {
            XCTAssertEqual(try JSONValue.double(number).text(), try encoded(.double(number)), "\(number)")
        }
        var every = ""
        for code in 0..<0x80 {
            every.unicodeScalars.append(Unicode.Scalar(UInt8(code)))
        }
        every += "\u{80}\u{9F}\u{A0}\u{2028}\u{2029}\u{FEFF}\u{E9}e\u{301}\u{1F600}"
        for escapingSlashes in [true, false] {
            XCTAssertEqual(try JSONValue.string(every).text(escapingSlashes: escapingSlashes),
                           try encoded(.string(every), escapingSlashes: escapingSlashes))
        }
        let keys = ["a10", "a2", "B", "b", "\u{E9}", "e", "_", "A", "\u{1F600}", "\u{FF21}", "Z", "a b", "10", "9", "\u{E8}", "", "k/\n",
                    "a\u{30A}", "\u{212B}"]
        let object = JSONValue.object(Dictionary(uniqueKeysWithValues: keys.map { ($0, JSONValue.array([.int(1), .null, .bool(false), .object([:])])) }))
        XCTAssertEqual(try object.text(sortedKeys: true), try encoded(object, sortedKeys: true))
        XCTAssertEqual(try parse(object.text()), object, "Unsorted, the keys come in any order")
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
        XCTAssertEqual(try JSONValue(any: Float(0.1))?.text(), "0.1", "A Float is written as its own shortest text")
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
