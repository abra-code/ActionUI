// Helpers/DictionaryCGFloatTests.swift
/*
 Tests for the [String: Any] readers cgFloat(forKey:) (Helpers/Dictionary+CGFloat.swift, Apple only)
 and for double(forKey:) reading a CGFloat a host set. The portable readers are tested in
 Core/DictionaryNumericTests.swift.
*/

import XCTest
import CoreGraphics
@testable import ActionUI

@MainActor
final class DictionaryCGFloatTests: XCTestCase {

    func testDoubleForKeyReadsACGFloat() {
        let dictionary: [String: Any] = ["cgfloat": CGFloat(8.75)]
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
    
    func testCGFloatForKeyWithMissingKey() {
        // Arrange: Empty dictionary
        let dictionary: [String: Any] = [:]
        
        // Act & Assert
        XCTAssertNil(
            dictionary.cgFloat(forKey: "missing"),
            "Should return nil for missing key"
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
}
