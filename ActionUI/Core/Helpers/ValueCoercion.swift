// Core/Helpers/ValueCoercion.swift
/*
 Brings a value parsed from JSON text to the type an element stores. JSON has one kind of number,
 and JSONValue gives an integral one as an Int, so a Slider (Double) set to 5 receives an Int that
 a renderer's `as? Double` would refuse. Foundation's NSNumber used to hide this by bridging to
 every numeric type.
*/

enum ValueCoercion {
    /// `value` as `valueType` when it is a number of another type, converted as Swift converts it
    /// (an Int beyond 2^53, or a Double to Float, rounds to the nearest value):
    /// - Double: from an Int or a Float.
    /// - Int: from a Double with no fractional part that fits.
    /// - Float: from an Int or a Double.
    /// An optional `valueType` (ProgressView stores `Double?`) is treated as its wrapped type.
    /// Everything else, including a value that already has the type, comes back unchanged. The
    /// numeric types are tested exactly, so on Apple an NSNumber is left to bridge as before.
    static func coerce(_ value: Any, to valueType: Any.Type) -> Any {
        let kind = type(of: value)
        if valueType == Double.self || valueType == Double?.self {
            if kind == Int.self, let number = value as? Int {
                return Double(number)
            }
            if kind == Float.self, let number = value as? Float {
                return Double(number)
            }
        } else if valueType == Int.self || valueType == Int?.self {
            if kind == Double.self, let number = value as? Double, let exact = Int(exactly: number) {
                return exact
            }
        } else if valueType == Float.self || valueType == Float?.self {
            if kind == Int.self, let number = value as? Int {
                return Float(number)
            }
            if kind == Double.self, let number = value as? Double {
                return Float(number)
            }
        }
        return value
    }
}
