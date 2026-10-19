// Helpers/Dictionary+Numeric.swift
/*
 Dictionary+Numeric.swift

 Extension for [String: Any] to handle numeric type coercion, ensuring properties expected as Double or CGFloat
 are retrieved correctly from JSON-parsed dictionaries, supporting Int, Int64, UInt, Double, Float, and CGFloat.
*/

import Foundation
import CoreGraphics

/// Numeric conversion of one JSON-decoded or runtime-set value, shared by the dictionary readers
/// below and by property parsers that receive a value rather than a dictionary.
enum JSONNumber {
    /// The value as a Double: Int, Double, Float, CGFloat, Int64, UInt, or the strings "inf" and
    /// "infinity" (any case). nil for anything else, including nil.
    static func double(_ value: Any?) -> Double? {
        guard let value else {
            return nil
        }

        switch value {
        case let intValue as Int:
            return Double(intValue)
        case let doubleValue as Double:
            return doubleValue
        case let floatValue as Float:
            return Double(floatValue)
        case let cgFloatValue as CGFloat:
            return Double(cgFloatValue)
        case let int64Value as Int64:
            return Double(int64Value)
        case let uintValue as UInt:
            return Double(uintValue)
        case let stringValue as String:
            let lower = stringValue.lowercased()
            if lower == "inf" || lower == "infinity" {
                return .infinity
            }
            return nil
        default:
            return nil
        }
    }

    /// The value as an Int: an Int, Int64 or UInt that fits, or a Double or Float with no
    /// fractional part that fits. nil for anything else, including nil.
    static func int(_ value: Any?) -> Int? {
        guard let value else {
            return nil
        }

        switch value {
        case let intValue as Int:
            return intValue
        case let int64Value as Int64:
            return Int(exactly: int64Value)
        case let uintValue as UInt:
            return Int(exactly: uintValue)
        case let doubleValue as Double:
            return Int(exactly: doubleValue)
        case let floatValue as Float:
            return Int(exactly: floatValue)
        default:
            return nil
        }
    }
}

extension [String: Any] {
    // Retrieves a value for the given key and converts it to Double if it's a numeric type.
    // Returns nil for non-numeric types.
    // Design decision: Supports scalable type coercion for JSON-parsed dictionaries, per JSON Property Flexibility.
    func double(forKey key: String) -> Double? {
        JSONNumber.double(self[key])
    }

    // Retrieves a value for the given key as an Int (see JSONNumber.int): integral numbers of any
    // numeric type, so a count written as 3.0, or set at runtime as an Int64, still reads as 3.
    func int(forKey key: String) -> Int? {
        JSONNumber.int(self[key])
    }

    // Retrieves a value for the given key and converts it to CGFloat if it's a numeric type.
    // Returns nil for non-numeric types, logging a warning via the provided logger.
    // Design decision: Ensures compatibility with SwiftUI modifiers expecting CGFloat, addressing CGFloat vs. Double mismatches.
    func cgFloat(forKey key: String) -> CGFloat? {
        guard let value = self[key] else {
            return nil
        }

        switch value {
        case let intValue as Int:
            return CGFloat(intValue)
        case let doubleValue as Double:
            return CGFloat(doubleValue)
        case let floatValue as Float:
            return CGFloat(floatValue)
        case let cgFloatValue as CGFloat:
            return cgFloatValue
        case let int64Value as Int64:
            return CGFloat(int64Value)
        case let uintValue as UInt:
            return CGFloat(uintValue)
        case let stringValue as String:
            let lower = stringValue.lowercased()
            if lower == "inf" || lower == "infinity" {
                return .infinity
            }
            return nil
        default:
            return nil
        }
    }
    
    func doubleArray(forKey key: String) -> [Double]? {
        guard let array = self[key] as? [Any] else { return nil }
        return array.map { ($0 as? NSNumber)?.doubleValue ?? 0.0 }
    }
    
    func cgFloatArray(forKey key: String) -> [CGFloat]? {
        guard let array = self[key] as? [Any] else { return nil }
        return array.map { CGFloat(($0 as? NSNumber)?.doubleValue ?? 0.0) }
    }
}
