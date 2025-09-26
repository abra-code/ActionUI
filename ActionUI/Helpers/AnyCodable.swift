/*
 AnyCodable.swift

 A helper type to enable Codable conformance for existential types (any Codable)
 used in ActionUIElementBase, such as properties and children collections.
 This type wraps arbitrary Codable values and provides encoding/decoding logic
 to support JSON serialization in the ActionUI component library.
*/

import Foundation

// A type-erasing wrapper for any Codable value to enable encoding and decoding
struct AnyCodable: Codable {
    let value: any Codable
    
    // Initializes with any Codable value
    init(_ value: any Codable) {
        self.value = value
    }
    
    // Decodes a Codable value from a decoder, handling nested structures
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try decoding common types first: String, Int, Bool, Double
        if let stringValue = try? container.decode(String.self) {
            self.value = stringValue
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self.value = intValue
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            self.value = boolValue
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self.value = doubleValue
            return
        }
        // Try decoding arrays and dictionaries of AnyCodable
        if let arrayValue = try? container.decode([AnyCodable].self) {
            self.value = arrayValue
            return
        }
        if let dictValue = try? container.decode([String: AnyCodable].self) {
            self.value = dictValue
            return
        }
        // Try decoding ViewElement for nested ActionUIElementBase
        if let elementValue = try? container.decode(ViewElement.self) {
            self.value = elementValue
            return
        }
        // Throw if no supported type matches
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported Codable type: \(container.codingPath)"
        )
    }
    
    // Encodes the wrapped value to an encoder, handling types in order of likelihood
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        // Handle common types first: String, Int, Bool, Double
        if let stringValue = value as? String {
            try container.encode(stringValue)
            return
        }
        if let intValue = value as? Int {
            try container.encode(intValue)
            return
        }
        if let boolValue = value as? Bool {
            try container.encode(boolValue)
            return
        }
        if let doubleValue = value as? Double {
            try container.encode(doubleValue)
            return
        }
        // Handle arrays and dictionaries
        if let arrayValue = value as? [AnyCodable] {
            try container.encode(arrayValue)
            return
        }
        if let dictValue = value as? [String: AnyCodable] {
            try container.encode(dictValue)
            return
        }
        // Handle ViewElement
        if let elementValue = value as? ViewElement {
            try container.encode(elementValue)
            return
        }
        // Throw if unsupported
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "Unsupported Codable type: \(type(of: value))"
            )
        )
    }
    
    // Converts the wrapped Codable value to an ActionUIElementBase, throwing if invalid
    func asActionUIElement() throws -> any ActionUIElementBase {
        if let element = value as? ViewElement {
            return element
        }
        throw DecodingError.typeMismatch(
            (any ActionUIElementBase).self,
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Expected ActionUIElementBase, got \(type(of: value))"
            )
        )
    }
    
    // Converts an AnyCodable to Any for properties
    static func convertAnyCodableToAny(_ anyCodable: AnyCodable) throws -> Any {
        switch anyCodable.value {
        case let stringValue as String:
            return stringValue
        case let intValue as Int:
            return intValue
        case let boolValue as Bool:
            return boolValue
        case let doubleValue as Double:
            return doubleValue
        case let dictValue as [String: AnyCodable]:
            return try dictValue.mapValues { try convertAnyCodableToAny($0) }
        case let arrayValue as [AnyCodable]:
            return try arrayValue.map { try convertAnyCodableToAny($0) }
        case let elementValue as ViewElement:
            return elementValue
        default:
            throw DecodingError.typeMismatch(
                type(of: anyCodable.value),
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported Codable type in properties: \(type(of: anyCodable.value))"
                )
            )
        }
    }
    
    // Converts Any to AnyCodable for encoding
    static func convertAnyToAnyCodable(_ value: Any) throws -> AnyCodable {
        switch value {
        case let stringValue as String:
            return AnyCodable(stringValue)
        case let intValue as Int:
            return AnyCodable(intValue)
        case let boolValue as Bool:
            return AnyCodable(boolValue)
        case let doubleValue as Double:
            return AnyCodable(doubleValue)
        case let dictValue as [String: Any]:
            return AnyCodable(try dictValue.mapValues { try convertAnyToAnyCodable($0) })
        case let arrayValue as [Any]:
            return AnyCodable(try arrayValue.map { try convertAnyToAnyCodable($0) })
        case let elementValue as ViewElement:
            return AnyCodable(elementValue)
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported type for encoding: \(type(of: value))"
                )
            )
        }
    }
}
