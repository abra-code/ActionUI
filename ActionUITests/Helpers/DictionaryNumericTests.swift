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
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
    }
    
    override func tearDown() {
        logger = nil
        super.tearDown()
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
}
