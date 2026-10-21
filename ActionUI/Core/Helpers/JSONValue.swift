// Core/Helpers/JSONValue.swift
/*
 A JSON value, decoded and encoded with JSONDecoder and JSONEncoder: FoundationEssentials, which
 Core builds against on Linux, has no JSONSerialization.

 Internal, like the verifier's own JSONValue (ActionUIVerifier/JSONValue.swift): a public type of
 this common name would collide with a host app's own JSONValue. The two are in separate modules,
 so they do not clash.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// JSON null in a Swift-native value tree, where Foundation would put NSNull (FoundationEssentials
/// has none). `JSONValue.anyValue` produces it for a JSON null, and `JSONValue(any:)` reads it back.
/// It describes itself as NSNull does, "<null>", so a value or state read as a string
/// (`getElementValueAsString`, `getElementStateAsString`) gives the text it gave as an NSNull,
/// alone or inside an array or dictionary.
public struct ActionUIJSONNull: Sendable, Hashable, CustomStringConvertible {
    public init() {}

    public var description: String { "<null>" }
}

enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Tries the kinds in this order: null, Bool, Int, Double, String, array, object. JSONDecoder
    /// gives an integral number (1, 1.0, 1e2) as an Int when asked for one, so every number that
    /// fits an Int without loss is `.int`, and the rest are `.double`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Int.self) {
            // A negative zero ("-0.0", "-0") also decodes as the Int 0; keep its sign.
            if number == 0, let double = try? container.decode(Double.self), double.sign == .minus {
                self = .double(double)
            } else {
                self = .int(number)
            }
        } else if let number = try? container.decode(Double.self) {
            self = .double(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let items = try? container.decode([JSONValue].self) {
            self = .array(items)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let flag):
            try container.encode(flag)
        case .int(let number):
            try container.encode(number)
        case .double(let number):
            try container.encode(number)
        case .string(let text):
            try container.encode(text)
        case .array(let items):
            try container.encode(items)
        case .object(let object):
            try container.encode(object)
        }
    }

    /// Parses JSON text; a bare string, number, bool or null is accepted as well as an array or
    /// object.
    init(parsing data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// The value as JSON text. Keys are in no fixed order unless `sortedKeys`; "/" is written as
    /// "\/" unless `escapingSlashes` is false. Throws for a non-finite double, which JSON cannot
    /// hold.
    func text(sortedKeys: Bool = false, escapingSlashes: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if sortedKeys {
            formatting.insert(.sortedKeys)
        }
        if !escapingSlashes {
            formatting.insert(.withoutEscapingSlashes)
        }
        encoder.outputFormatting = formatting
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    /// The Swift-native form: Bool, Int, Double, String, [Any], [String: Any], or ActionUIJSONNull.
    var anyValue: Any {
        switch self {
        case .null:
            return ActionUIJSONNull()
        case .bool(let flag):
            return flag
        case .int(let number):
            return number
        case .double(let number):
            return number
        case .string(let text):
            return text
        case .array(let items):
            return items.map(\.anyValue)
        case .object(let object):
            return object.mapValues(\.anyValue)
        }
    }

    /// From a Swift-native value: Bool; any integer type (`.int`, or `.double` for a value beyond
    /// Int's range); any floating-point type, CGFloat among them (`.double`); String;
    /// ActionUIJSONNull; an Optional (nil is `.null`); and arrays and string-keyed dictionaries of
    /// them. nil for anything else (a Date, a color, a coordinate). The scalar types are tested by
    /// their Swift type (an NSNumber does not cast to BinaryInteger), so on Apple an NSNumber is
    /// refused rather than bridged;
    /// FoundationBridge.native converts one first.
    init?(any value: Any) {
        if type(of: value) == Bool.self, let flag = value as? Bool {
            self = .bool(flag)
        } else if let number = value as? any BinaryInteger {
            self = Int(exactly: number).map { .int($0) } ?? .double(Double(number))
        } else if let number = value as? any BinaryFloatingPoint {
            self = .double(Double(number))
        } else if let unwrapped = Self.unwrappedOptional(value) {
            guard let inner = unwrapped else {
                self = .null
                return
            }
            guard let converted = JSONValue(any: inner) else { return nil }
            self = converted
        } else if let text = value as? String {
            self = .string(text)
        } else if value is ActionUIJSONNull {
            self = .null
        } else if let items = value as? [Any] {
            var converted: [JSONValue] = []
            converted.reserveCapacity(items.count)
            for item in items {
                guard let element = JSONValue(any: item) else { return nil }
                converted.append(element)
            }
            self = .array(converted)
        } else if let object = value as? [String: Any] {
            var converted: [String: JSONValue] = [:]
            converted.reserveCapacity(object.count)
            for (key, item) in object {
                guard let element = JSONValue(any: item) else { return nil }
                converted[key] = element
            }
            self = .object(converted)
        } else {
            return nil
        }
    }

    // The wrapped value of an Optional held in an Any: .some(inner), or .some(nil) for nil.
    // nil when `value` is not an Optional. A non-nil Optional already casts to its wrapped type,
    // so this matters for nil and for wrapped values the casts above do not take.
    private static func unwrappedOptional(_ value: Any) -> Any?? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        return .some(mirror.children.first?.value)
    }
}
