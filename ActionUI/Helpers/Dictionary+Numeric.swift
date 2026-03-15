// Helpers/Dictionary+Numeric.swift
/*
 Dictionary+Numeric.swift

 Extension for [String: Any] to handle numeric type coercion, ensuring properties expected as Double or CGFloat
 are retrieved correctly from JSON-parsed dictionaries, supporting Int, Int64, UInt, Double, Float, and CGFloat.
*/

import Foundation
import CoreGraphics

extension [String: Any] {
    // Retrieves a value for the given key and converts it to Double if it's a numeric type.
    // Returns nil for non-numeric types, logging a warning via the provided logger.
    // Design decision: Supports scalable type coercion for JSON-parsed dictionaries, per JSON Property Flexibility.
    func double(forKey key: String) -> Double? {
        guard let value = self[key] else {
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
