// Core/Helpers/JSONHelper.swift
/*
 JSONHelper tells whether a string could be JSON text, for converting strings to typed values
 without a statically known target type.
 */

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

class JSONHelper {
    /// Returns true if the string's first character suggests it could be a JSON fragment.
    /// Used to skip JSON parsing, and the cost of a failed parse, for plain strings, which are
    /// the most common expected type.
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
}
