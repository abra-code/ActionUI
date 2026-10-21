// Common/FoundationBridge.swift
/*
 Converts between Foundation's object values (NSNumber, NSString, NSNull, NSArray, NSDictionary),
 which still reach ActionUI on Apple from Objective-C hosts and from JSONSerialization, and the
 Swift-native values Core works with (Core/Helpers/JSONValue.swift). Apple only: there is no
 NSNumber in FoundationEssentials.
*/

import Foundation

enum FoundationBridge {
    /// `value` with every Foundation value inside it made Swift-native: a boolean NSNumber becomes
    /// Bool; another NSNumber becomes Int when it is an integer or an integral floating-point
    /// number that fits, else Double; NSString becomes String; NSNull becomes ActionUIJSONNull;
    /// arrays and string-keyed dictionaries are converted element by element. Swift values and
    /// anything else (a Date, a color) come back unchanged.
    static func native(_ value: Any) -> Any {
        let kind = type(of: value)
        // Swift scalars first: a Swift Bool or Int would also pass `as? NSNumber`, by bridging.
        if kind == Bool.self || kind == Int.self || kind == Double.self || kind == Float.self || kind == String.self {
            return value
        }
        if let number = value as? NSNumber {
            return native(number)
        }
        if let text = value as? String {
            return text
        }
        if value is NSNull {
            return ActionUIJSONNull()
        }
        if let items = value as? [Any] {
            return items.map(native)
        }
        if let object = value as? [String: Any] {
            return object.mapValues(native)
        }
        return value
    }

    private static func native(_ number: NSNumber) -> Any {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        switch UInt8(bitPattern: number.objCType.pointee) {
        case UInt8(ascii: "f"), UInt8(ascii: "d"):
            let double = number.doubleValue
            // Negative zero stays a Double, keeping its sign as JSONValue does.
            if double == 0, double.sign == .minus {
                return double
            }
            return Int(exactly: double) ?? double
        case UInt8(ascii: "Q"), UInt8(ascii: "L"), UInt8(ascii: "I"):
            // An unsigned integer above Int.max has no Int; keep its value as a Double.
            return Int(exactly: number.uint64Value) ?? number.doubleValue
        default:
            return number.intValue
        }
    }

    /// `value` with every ActionUIJSONNull inside it turned back into NSNull, for an Objective-C
    /// host. Everything else comes back unchanged.
    static func foundation(_ value: Any) -> Any {
        if value is ActionUIJSONNull {
            return NSNull()
        }
        if let items = value as? [Any] {
            return items.map(foundation)
        }
        if let object = value as? [String: Any] {
            return object.mapValues(foundation)
        }
        return value
    }
}
