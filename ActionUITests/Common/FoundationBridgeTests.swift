// Tests/Common/FoundationBridgeTests.swift
/*
 Tests for FoundationBridge: what JSONSerialization and Objective-C hosts hand ActionUI on Apple
 becomes the Swift-native values Core works with, and back.
*/

import Foundation
import XCTest
@testable import ActionUI

final class FoundationBridgeTests: XCTestCase {

    private func serialized(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    func testJSONSerializationScalars() throws {
        let cases: [(String, JSONValue)] = [
            ("true", .bool(true)), ("false", .bool(false)), ("1", .int(1)), ("0", .int(0)),
            ("1.5", .double(1.5)), ("2.0", .int(2)), ("-7", .int(-7)), ("0.1", .double(0.1)),
            ("null", .null), (#""s""#, .string("s")),
        ]
        for (text, expected) in cases {
            let native = FoundationBridge.native(try serialized(text))
            XCTAssertEqual(JSONValue(any: native), expected, text)
        }
    }

    func testJSONSerializationNested() throws {
        let native = FoundationBridge.native(try serialized(#"[true,0,{"k":[1,null,"a"]},[]]"#))
        XCTAssertEqual(JSONValue(any: native), .array([
            .bool(true), .int(0), .object(["k": .array([.int(1), .null, .string("a")])]), .array([]),
        ]))
    }

    func testBooleansAndNumbersStayApart() {
        XCTAssertTrue(type(of: FoundationBridge.native(NSNumber(value: true))) == Bool.self)
        XCTAssertTrue(type(of: FoundationBridge.native(NSNumber(value: 1))) == Int.self)
        XCTAssertTrue(type(of: FoundationBridge.native(NSNumber(value: Int8(1)))) == Int.self, "A char-typed NSNumber is a number, not a Bool")
        XCTAssertTrue(type(of: FoundationBridge.native(NSNumber(value: 1.25))) == Double.self)
        XCTAssertTrue(type(of: FoundationBridge.native(NSNumber(value: Float(3)))) == Int.self)
    }

    // JSONSerialization gives "-0.0" as a negative-zero double; it keeps its sign, as in JSONValue.
    func testNegativeZeroKeepsItsSign() throws {
        let zero = try XCTUnwrap(FoundationBridge.native(try serialized("-0.0")) as? Double)
        XCTAssertEqual(zero.sign, .minus)
        XCTAssertEqual(JSONValue(any: zero), try JSONValue(parsing: Data("-0.0".utf8)))
    }

    func testLargeIntegers() {
        XCTAssertEqual(FoundationBridge.native(NSNumber(value: Int64.max)) as? Int, Int.max)
        XCTAssertEqual(FoundationBridge.native(NSNumber(value: UInt64(Int.max))) as? Int, Int.max)
        XCTAssertEqual(FoundationBridge.native(NSNumber(value: UInt64.max)) as? Double, Double(UInt64.max))
    }

    func testSwiftValuesAndOthersAreUnchanged() {
        XCTAssertTrue(type(of: FoundationBridge.native(true)) == Bool.self)
        XCTAssertTrue(type(of: FoundationBridge.native(5)) == Int.self)
        XCTAssertTrue(type(of: FoundationBridge.native(2.0)) == Double.self, "A Swift Double stays a Double")
        XCTAssertTrue(type(of: FoundationBridge.native(Float(2))) == Float.self)
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(FoundationBridge.native(date) as? Date, date)
        XCTAssertTrue(type(of: FoundationBridge.native(NSString(string: "x"))) == String.self)
    }

    func testJSONValueRefusesNSNumber() {
        XCTAssertNil(JSONValue(any: NSNumber(value: 1)), "An NSNumber must go through FoundationBridge.native first")
        XCTAssertNil(JSONValue(any: NSNull()))
        XCTAssertEqual(JSONValue(any: CGFloat(2.5)), .double(2.5), "A Swift CGFloat is a floating-point number")
    }

    func testBackToFoundation() throws {
        let value = FoundationBridge.foundation([ActionUIJSONNull(), ["k": ActionUIJSONNull(), "n": 1] as [String: Any], "s"] as [Any])
        let items = try XCTUnwrap(value as? [Any])
        XCTAssertTrue(items[0] is NSNull)
        let object = try XCTUnwrap(items[1] as? [String: Any])
        XCTAssertTrue(object["k"] is NSNull)
        XCTAssertEqual(object["n"] as? Int, 1)
        XCTAssertEqual(items[2] as? String, "s")
        XCTAssertTrue(FoundationBridge.foundation(ActionUIJSONNull()) is NSNull)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(value), "The result is what JSONSerialization accepts")
    }
}
