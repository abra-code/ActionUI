// Helpers/Dictionary+CGFloat.swift
/*
 The CGFloat readers of [String: Any], for SwiftUI modifiers that take CGFloat. Apple only: the
 portable numeric readers (double, int, doubleArray) are in Core/Helpers/Dictionary+Numeric.swift.
*/

import CoreGraphics
import Foundation

extension [String: Any] {
    // Retrieves a value for the given key and converts it to CGFloat if it's a numeric type.
    // Returns nil for non-numeric types.
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

    func cgFloatArray(forKey key: String) -> [CGFloat]? {
        guard let array = self[key] as? [Any] else { return nil }
        return array.map { CGFloat(($0 as? NSNumber)?.doubleValue ?? 0.0) }
    }
}
