// Core/FieldComparison.swift
/*
 Compares two values of the same struct field by field, through Mirror: Equatable fields with ==
 (so the order of a Set does not matter), the rest - such as an Any? holding a raw JSON value - by
 their description. Each differing field is reported by name.

 Used to check that parsing raw properties and parsing the same properties after validation give
 the same result, for BaseModifiers and the elements' Props.
*/

import XCTest

func assertSameFields<T>(
    _ actual: T,
    _ expected: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actualFields = Array(Mirror(reflecting: actual).children)
    let expectedFields = Array(Mirror(reflecting: expected).children)
    XCTAssertEqual(actualFields.count, expectedFields.count, "field count \(message())", file: file, line: line)
    for (actualField, expectedField) in zip(actualFields, expectedFields) {
        if !sameFieldValue(actualField.value, expectedField.value) {
            XCTFail("\(actualField.label ?? "?"): \(actualField.value) is not \(expectedField.value) \(message())", file: file, line: line)
        }
    }
}

private func sameFieldValue(_ lhs: Any, _ rhs: Any) -> Bool {
    if let equatable = lhs as? any Equatable {
        return isEqual(equatable, rhs)
    }
    return String(describing: lhs) == String(describing: rhs)
}

private func isEqual<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool {
    guard let rhs = rhs as? T else {
        return false
    }
    return lhs == rhs
}
