// Tests/DictionaryNumericTests.swift
/*
 DictionaryNumericTests.swift

 Tests for [String: Any] extension methods double(forKey:logger:) and cgFloat(forKey:logger:).
 Verifies numeric type coercion for Int, Int64, UInt, Double, Float, and CGFloat, handling of non-numeric types,
 missing keys, and edge cases, ensuring compatibility with JSON-parsed dictionaries.
 Focuses on result correctness without verifying log messages.
*/

import XCTest
import CoreGraphics
@testable import ActionUI

@MainActor
final class DictionaryNumericTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
    }
    
    override func tearDown() async throws {
        logger = nil
        try await super.tearDown()
    }
    
    func testDoubleForKeyWithValidNumericTypes() {
        // Arrange: Dictionary with various numeric types
        let dictionary: [String: Any] = [
            "int": 8,
            "int64": Int64(8),
            "uint": UInt(8),
            "double": 8.5,
            "float": Float(8.25),
            "cgfloat": CGFloat(8.75)
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
        XCTAssertEqual(
            dictionary.double(forKey: "cgfloat"),
            8.75,
            "Should coerce CGFloat to Double with value 8.75"
        )
    }
    
    func testCGFloatForKeyWithValidNumericTypes() {
        // Arrange: Dictionary with various numeric types
        let dictionary: [String: Any] = [
            "int": 8,
            "int64": Int64(8),
            "uint": UInt(8),
            "double": 8.5,
            "float": Float(8.25),
            "cgfloat": CGFloat(8.75)
        ]
        
        // Act & Assert: Test each numeric type
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "int"),
            8.0,
            "Should coerce Int to CGFloat with value 8.0"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "int64"),
            8.0,
            "Should coerce Int64 to CGFloat with value 8.0"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "uint"),
            8.0,
            "Should coerce UInt to CGFloat with value 8.0"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "double"),
            8.5,
            "Should coerce Double to CGFloat with value 8.5"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "float"),
            8.25,
            "Should coerce Float to CGFloat with value 8.25"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "cgfloat"),
            8.75,
            "Should return CGFloat with value 8.75"
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
    
    func testCGFloatForKeyWithNonNumericTypes() {
        // Arrange: Dictionary with non-numeric types
        let dictionary: [String: Any] = [
            "string": "8.0",
            "bool": true,
            "array": [1, 2, 3]
        ]
        
        // Act & Assert: Test each non-numeric type
        XCTAssertNil(
            dictionary.cgFloat(forKey: "string"),
            "Should return nil for String value"
        )
        XCTAssertNil(
            dictionary.cgFloat(forKey: "bool"),
            "Should return nil for Bool value"
        )
        XCTAssertNil(
            dictionary.cgFloat(forKey: "array"),
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
    
    func testCGFloatForKeyWithMissingKey() {
        // Arrange: Empty dictionary
        let dictionary: [String: Any] = [:]
        
        // Act & Assert
        XCTAssertNil(
            dictionary.cgFloat(forKey: "missing"),
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

    func testCGFloatForKeyWithInfinityStrings() {
        let dictionary: [String: Any] = [
            "inf": "inf",
            "infinity": "infinity",
            "INF": "INF",
            "Infinity": "Infinity",
            "notInf": "infinite",
            "numeric": "8.0"
        ]

        XCTAssertEqual(
            dictionary.cgFloat(forKey: "inf"),
            .infinity,
            "Should return .infinity for 'inf'"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "infinity"),
            .infinity,
            "Should return .infinity for 'infinity'"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "INF"),
            .infinity,
            "Should return .infinity for 'INF' (case-insensitive)"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "Infinity"),
            .infinity,
            "Should return .infinity for 'Infinity' (case-insensitive)"
        )
        XCTAssertNil(
            dictionary.cgFloat(forKey: "notInf"),
            "Should return nil for 'infinite' (not a recognized infinity string)"
        )
        XCTAssertNil(
            dictionary.cgFloat(forKey: "numeric"),
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
    
    func testCGFloatForKeyWithEdgeCases() {
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
            dictionary.cgFloat(forKey: "zero"),
            0.0,
            "Should coerce zero to CGFloat"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "negative"),
            -8.5,
            "Should handle negative CGFloat"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "large"),
            1_000_000.25,
            "Should handle large CGFloat"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "largeInt64"),
            1_000_000.0,
            "Should coerce large Int64 to CGFloat"
        )
        XCTAssertEqual(
            dictionary.cgFloat(forKey: "largeUInt"),
            1_000_000.0,
            "Should coerce large UInt to CGFloat"
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
