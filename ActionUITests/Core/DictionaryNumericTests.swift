// Core/DictionaryNumericTests.swift
/*
 DictionaryNumericTests.swift

 Tests for the [String: Any] readers double(forKey:) and int(forKey:) and for JSONNumber.
 Verifies numeric type coercion for Int, Int64, UInt, Double and Float, handling of non-numeric types,
 missing keys, and edge cases, ensuring compatibility with JSON-parsed dictionaries.
 (The CGFloat readers, Apple only, are tested in Helpers/DictionaryCGFloatTests.swift.)
*/

import XCTest
@testable import ActionUI

@MainActor
final class DictionaryNumericTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        logger = XCTestLogger(maxLevel: .verbose)
    }
    
    override func tearDown() async throws {
        logger = nil
    }
    
    func testDoubleForKeyWithValidNumericTypes() {
        // Arrange: Dictionary with various numeric types
        let dictionary: [String: Any] = [
            "int": 8,
            "int64": Int64(8),
            "uint": UInt(8),
            "double": 8.5,
            "float": Float(8.25)
        ]
        
        // Act & Assert: Test each numeric type
        XCTAssertEqual(
            dictionary.double(forKey: "int"),
            8.0,
            "Should coerce Int to Double with value 8.0"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "int64"),
            8.0,
            "Should coerce Int64 to Double with value 8.0"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "uint"),
            8.0,
            "Should coerce UInt to Double with value 8.0"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "double"),
            8.5,
            "Should return Double with value 8.5"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "float"),
            8.25,
            "Should coerce Float to Double with value 8.25"
        )
    }
    
    func testDoubleForKeyWithNonNumericTypes() {
        // Arrange: Dictionary with non-numeric types
        let dictionary: [String: Any] = [
            "string": "8.0",
            "bool": true,
            "array": [1, 2, 3]
        ]
        
        // Act & Assert: Test each non-numeric type
        XCTAssertNil(
            dictionary.double(forKey: "string"),
            "Should return nil for String value"
        )
        XCTAssertNil(
            dictionary.double(forKey: "bool"),
            "Should return nil for Bool value"
        )
        XCTAssertNil(
            dictionary.double(forKey: "array"),
            "Should return nil for Array value"
        )
    }
    
    func testDoubleForKeyWithMissingKey() {
        // Arrange: Empty dictionary
        let dictionary: [String: Any] = [:]
        
        // Act & Assert
        XCTAssertNil(
            dictionary.double(forKey: "missing"),
            "Should return nil for missing key"
        )
    }
    
    func testDoubleForKeyWithInfinityStrings() {
        let dictionary: [String: Any] = [
            "inf": "inf",
            "infinity": "infinity",
            "INF": "INF",
            "Infinity": "Infinity",
            "notInf": "infinite",
            "numeric": "8.0"
        ]

        XCTAssertEqual(
            dictionary.double(forKey: "inf"),
            .infinity,
            "Should return .infinity for 'inf'"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "infinity"),
            .infinity,
            "Should return .infinity for 'infinity'"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "INF"),
            .infinity,
            "Should return .infinity for 'INF' (case-insensitive)"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "Infinity"),
            .infinity,
            "Should return .infinity for 'Infinity' (case-insensitive)"
        )
        XCTAssertNil(
            dictionary.double(forKey: "notInf"),
            "Should return nil for 'infinite' (not a recognized infinity string)"
        )
        XCTAssertNil(
            dictionary.double(forKey: "numeric"),
            "Should return nil for '8.0' (numeric strings are not parsed)"
        )
    }

    func testDoubleForKeyWithEdgeCases() {
        // Arrange: Dictionary with edge case numeric values
        let dictionary: [String: Any] = [
            "zero": 0,
            "negative": -8.5,
            "large": 1_000_000.25,
            "largeInt64": Int64(1_000_000),
            "largeUInt": UInt(1_000_000)
        ]
        
        // Act & Assert
        XCTAssertEqual(
            dictionary.double(forKey: "zero"),
            0.0,
            "Should coerce zero to Double"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "negative"),
            -8.5,
            "Should handle negative Double"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "large"),
            1_000_000.25,
            "Should handle large Double"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "largeInt64"),
            1_000_000.0,
            "Should coerce large Int64 to Double"
        )
        XCTAssertEqual(
            dictionary.double(forKey: "largeUInt"),
            1_000_000.0,
            "Should coerce large UInt to Double"
        )
    }
    
    func testIntForKeyAcceptsIntegralNumbersOfAnyType() {
        let dictionary: [String: Any] = [
            "int": 3,
            "int64": Int64(3),
            "uint": UInt(3),
            "integralDouble": 3.0,
            "integralFloat": Float(3),
            "negative": -2,
        ]
        XCTAssertEqual(dictionary.int(forKey: "int"), 3)
        XCTAssertEqual(dictionary.int(forKey: "int64"), 3)
        XCTAssertEqual(dictionary.int(forKey: "uint"), 3)
        XCTAssertEqual(dictionary.int(forKey: "integralDouble"), 3)
        XCTAssertEqual(dictionary.int(forKey: "integralFloat"), 3)
        XCTAssertEqual(dictionary.int(forKey: "negative"), -2)
    }

    func testIntForKeyRefusesFractionsOutOfRangeAndNonNumbers() {
        let dictionary: [String: Any] = [
            "fraction": 3.5,
            "huge": 1e300,
            "infinity": Double.infinity,
            "hugeUInt": UInt.max,
            "string": "3",
            "bool": true,
        ]
        XCTAssertNil(dictionary.int(forKey: "fraction"))
        XCTAssertNil(dictionary.int(forKey: "huge"))
        XCTAssertNil(dictionary.int(forKey: "infinity"))
        XCTAssertNil(dictionary.int(forKey: "hugeUInt"))
        XCTAssertNil(dictionary.int(forKey: "string"))
        XCTAssertNil(dictionary.int(forKey: "bool"))
        XCTAssertNil(dictionary.int(forKey: "missing"))
    }

    func testJSONNumberConvertsSingleValues() {
        XCTAssertEqual(JSONNumber.double(5), 5)
        XCTAssertEqual(JSONNumber.double(2.5), 2.5)
        XCTAssertEqual(JSONNumber.double("Infinity"), .infinity)
        XCTAssertNil(JSONNumber.double("5"))
        XCTAssertNil(JSONNumber.double(nil))
        XCTAssertEqual(JSONNumber.int(4.0), 4)
        XCTAssertNil(JSONNumber.int(4.5))
        XCTAssertNil(JSONNumber.int(nil))
    }
}
