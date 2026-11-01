// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// JSONValue.swift - the verifier's own JSON value, built from JSONSerialization output, or from
// JSONText.swift's parser on Linux, which has no JSONSerialization. Internal: the public API takes
// Data or parsed objects, so a client with its own JSON type does not get two types of the same name.
//
// Integers and non-integers stay apart ("integer" vs "number" in the schemas, int vs float in the
// Python verifier's messages), and on Apple NSNumber booleans are told apart from numbers by their
// CF type.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parses JSON text as ActionUI's loader does: a trailing comma is accepted, a comment is not.
    /// Throws for invalid JSON.
    init(parsing data: Data) throws {
        #if os(Linux)
        self = try JSONTextParser.parse(data)
        #else
        self = JSONValue(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        #endif
    }

    /// Converts a parsed object: on Apple JSONSerialization's, on Linux Bool, the number types,
    /// String, [Any] and [String: Any]. Anything that is not a JSON value becomes null.
    init(any value: Any) {
        switch value {
        #if os(Linux)
        case let flag as Bool:
            self = .bool(flag)
        case let number as Int:
            self = .int(number)
        case let number as Double:
            self = .double(number)
        case let number as any BinaryInteger:
            self = Int(exactly: number).map { .int($0) } ?? .double(Double(number))
        case let number as any BinaryFloatingPoint:
            self = .double(Double(number))
        #else
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                switch UInt8(bitPattern: number.objCType.pointee) {
                case UInt8(ascii: "f"), UInt8(ascii: "d"):
                    self = .double(number.doubleValue)
                default:
                    self = .int(number.intValue)
                }
            }
        #endif
        case let text as String:
            self = .string(text)
        case let items as [Any]:
            self = .array(items.map(JSONValue.init(any:)))
        case let object as [String: Any]:
            self = .object(object.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    var object: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let items) = self {
            return items
        }
        return nil
    }

    var string: String? {
        if case .string(let text) = self {
            return text
        }
        return nil
    }

    var bool: Bool? {
        if case .bool(let flag) = self {
            return flag
        }
        return nil
    }

    /// Integers and non-integers as a Double, for comparing numbers by value.
    var double: Double? {
        switch self {
        case .int(let number):
            return Double(number)
        case .double(let number):
            return number
        default:
            return nil
        }
    }

    var stringArray: [String]? { array?.compactMap(\.string) }

    subscript(key: String) -> JSONValue? { object?[key] }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
                     ExpressibleByDictionaryLiteral {
    init(nilLiteral: ()) { self = .null }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(stringLiteral value: String) { self = .string(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
