/*
 JSONHelper provides utility functions for JSON fragment detection and value normalisation.
 Used when converting strings to typed values without a statically known target type.
 */

import Foundation

class JSONHelper {
    /// Returns true if the string's first character suggests it could be a JSON fragment.
    /// Used to skip JSON parsing — and its NSError allocation cost — for plain strings,
    /// which are the most common expected type.
    static func looksLikeJSONFragment(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first else { return false }
        switch first {
        case "{", "[":        return true  // object, array
        case "\"":            return true  // quoted string fragment
        case "t", "f", "n":  return true  // true, false, null
        case "0"..."9", "-": return true  // number
        default:             return false
        }
    }

    /// Bridges NSNumber/NSString from JSONSerialization to Swift-native types so that
    /// type(of:) comparisons on the result match types stored by Swift code.
    /// - NSNumber booleans  → Bool
    /// - NSNumber whole numbers → Int
    /// - NSNumber fractional → Double
    /// - NSString → String
    /// - Everything else (NSArray, NSDictionary, NSNull) is returned as-is.
    static func normalizedJSONValue(_ value: Any) -> Any {
        switch value {
        case let n as NSNumber:
            // CFBooleanGetTypeID() distinguishes true/false NSNumbers from numeric ones.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            // Prefer Int for whole numbers, Double otherwise.
            let d = n.doubleValue
            let i = n.intValue
            return d == Double(i) ? i : d
        case let s as NSString:
            return s as String
        default:
            return value
        }
    }
}
