// Core/ValueCoercionTests.swift
/*
 Tests for ValueCoercion: a number parsed from JSON reaches an element as the type it stores.
*/

import XCTest
@testable import ActionUI

final class ValueCoercionTests: XCTestCase {

    private func coerced(_ value: Any, to valueType: Any.Type) -> String {
        let result = ValueCoercion.coerce(value, to: valueType)
        return "\(type(of: result)) \(result)"
    }

    func testToDouble() {
        XCTAssertEqual(coerced(5, to: Double.self), "Double 5.0")
        XCTAssertEqual(coerced(Float(0.5), to: Double.self), "Double 0.5")
        XCTAssertEqual(coerced(2.5, to: Double.self), "Double 2.5")
        XCTAssertEqual(coerced("5", to: Double.self), "String 5", "A string is not a number")
        XCTAssertEqual(coerced(true, to: Double.self), "Bool true", "A Bool is not a number")
    }

    func testToInt() {
        XCTAssertEqual(coerced(2.0, to: Int.self), "Int 2")
        XCTAssertEqual(coerced(-3.0, to: Int.self), "Int -3")
        XCTAssertEqual(coerced(2.5, to: Int.self), "Double 2.5", "A fraction is not cut off")
        XCTAssertEqual(coerced(1e300, to: Int.self), "Double 1e+300", "Too large for an Int")
        XCTAssertEqual(coerced(7, to: Int.self), "Int 7")
        XCTAssertEqual(coerced(Float(2), to: Int.self), "Float 2.0", "Only a Double becomes an Int")
    }

    func testToFloat() {
        XCTAssertEqual(coerced(3, to: Float.self), "Float 3.0")
        XCTAssertEqual(coerced(0.25, to: Float.self), "Float 0.25")
        XCTAssertEqual(coerced(Float(1.5), to: Float.self), "Float 1.5")
    }

    // ProgressView stores Double? and NavigationLink Int?: an optional type coerces as its wrapped type.
    func testToOptionalTypes() {
        XCTAssertEqual(coerced(1, to: Double?.self), "Double 1.0")
        XCTAssertEqual(coerced(2.0, to: Int?.self), "Int 2")
        XCTAssertEqual(coerced(3, to: Float?.self), "Float 3.0")
    }

    func testOtherTypesAreUnchanged() {
        XCTAssertEqual(coerced(5, to: String.self), "Int 5")
        XCTAssertEqual(coerced(1, to: Bool.self), "Int 1", "An Int never becomes a Bool")
        XCTAssertEqual(coerced(["a"], to: [String].self), "Array<String> [\"a\"]")
        XCTAssertEqual(coerced(5, to: Void.self), "Int 5")
    }
}
