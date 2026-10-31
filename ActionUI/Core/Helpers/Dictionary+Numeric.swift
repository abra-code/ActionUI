// Core/Helpers/Dictionary+Numeric.swift
/*
 Dictionary+Numeric.swift

 Extension for [String: Any] to handle numeric type coercion, ensuring properties expected as Double or CGFloat
 are retrieved correctly from JSON-parsed dictionaries, supporting Int, Int64, UInt, Double, Float, and (on
 Apple, where Foundation has it) CGFloat. The CGFloat readers are in Helpers/Dictionary+CGFloat.swift.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
#if !canImport(FoundationEssentials)
        // A CGFloat set at runtime by a host; FoundationEssentials has no CGFloat.
        case let cgFloatValue as CGFloat:
            return Double(cgFloatValue)
#endif
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

    /// The value as a Double when it is a number and not a boolean. On Apple, JSON true and false
    /// can arrive as an NSNumber, which casts to Int and Double, so only its CF type tells them apart.
    static func plain(_ value: Any?) -> Double? {
#if canImport(FoundationEssentials)
        // Every integer and floating-point type, as an NSNumber takes them on Apple.
        if let number = value as? any BinaryInteger {
            return Double(number)
        }
        if let number = value as? any BinaryFloatingPoint {
            return Double(number)
        }
        return nil
#else
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number.doubleValue
#endif
    }

    /// The value as a Double when it is a number or a boolean (0 or 1), as an NSNumber reads either.
    static func numberOrBoolean(_ value: Any?) -> Double? {
#if canImport(FoundationEssentials)
        if let flag = value as? Bool {
            return flag ? 1 : 0
        }
        return plain(value)
#else
        return (value as? NSNumber)?.doubleValue
#endif
    }

    /// Whether the value is a boolean: a Bool, or on Apple a boolean NSNumber.
    static func isBoolean(_ value: Any?) -> Bool {
#if canImport(FoundationEssentials)
        return value is Bool
#else
        guard let number = value as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
#endif
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

    // Each element read by JSONNumber.double, as double(forKey:) reads one value; 0 for an element
    // that is not a number.
    func doubleArray(forKey key: String) -> [Double]? {
        guard let array = self[key] as? [Any] else { return nil }
        return array.map { JSONNumber.double($0) ?? 0.0 }
    }
}
