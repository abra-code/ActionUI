// Views/PropsValidation/PropsValidationSupport.swift
/*
 An element's Props built from raw properties must equal its Props built from the same properties
 after the registry's validation (the base View validation, then the element's own). That is what
 lets renderers read raw properties: Props lets through exactly what validation let through.

 Each element's test lists values per key, written the way JSON decoding produces them (Int for
 integral numbers, [String: Any] for objects, [Any] for arrays), and, where keys interact,
 whole property sets.
*/

import XCTest
@testable import ActionUI

@MainActor
func assertPropsMatchValidation<P>(
    elementType: String,
    _ makeProps: ([String: Any]) -> P,
    casesByKey: [String: [Any]],
    combinations: [[String: Any]] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let registry = ActionUIRegistry.shared
    for (key, values) in casesByKey {
        for (index, value) in values.enumerated() {
            let raw: [String: Any] = [key: value]
            assertSameFields(
                makeProps(raw),
                makeProps(registry.validateProperties(forElementType: elementType, properties: raw)),
                "\(elementType) \(key) case \(index): \(value)",
                file: file, line: line
            )
        }
    }
    for (index, raw) in combinations.enumerated() {
        assertSameFields(
            makeProps(raw),
            makeProps(registry.validateProperties(forElementType: elementType, properties: raw)),
            "\(elementType) combination \(index): \(raw)",
            file: file, line: line
        )
    }
}

/// The standard setUp for these tests. Validation logs a warning for every invalid case; the
/// registry's logger is left as it is, because it outlives the test.
@MainActor
class PropsValidationTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        try await super.tearDown()
    }
}
