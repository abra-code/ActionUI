// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// JSONText.swift - JSON text to JSONValue on Linux, whose FoundationEssentials has no
// JSONSerialization. Built on every platform, so the tests can hold it against JSONSerialization.
//
// Why not ActionUI's parser: this library does not depend on ActionUI, so the verifier runs where
// GTK is not installed; and that parser gives 1.0 as an integer, where the schemas tell "integer"
// from "number", as the Python verifier and JSONSerialization do. JSONDecoder has the same
// problem.
//
// It reads what JSONSerialization reads: a trailing comma in an array or object, a UTF-8 byte order
// mark, UTF-16 and UTF-32 text, the first of a repeated key, a bare string, number, bool or null,
// nesting to 512 levels (an empty array or object may sit one level deeper). A number with a
// fraction or an exponent is a double, any other that fits an Int is an integer, and so is one up
// to UInt64.max, wrapped to an Int as JSONValue(any:) wraps it. A number too large for a double is
// refused, except that a negative one is negative infinity.
//
// JSONSerialization quirks it does not copy: a lone byte 0xA9 in a string, which that accepts and
// no other invalid UTF-8; a U+FEFF at the start of a string, which that drops; an exponent of four
// digits or more, some of which that refuses (1e-0000); digits past the 17th of a double, which
// that does not round correctly. ActionUI's parser does none of these either.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Text that is not JSON: what was wrong, and the byte offset where the parser found it.
struct JSONTextError: Error, CustomStringConvertible {
    let message: String
    let offset: Int

    var description: String { "\(message) at byte \(offset)" }
}

struct JSONTextParser {
    /// The deepest nesting accepted, JSONSerialization's limit.
    static let maximumDepth = 512

    static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONTextParser(bytes: try utf8Bytes(of: data))
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            parser.index = 3
        }
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.failure("Unexpected text after the JSON value") }
        return value
    }

    /// The text as UTF-8. UTF-16 and UTF-32 are told as JSONSerialization tells them: by a byte
    /// order mark, or by the zero bytes among the first four when there are more than four. (A
    /// UTF-32 little-endian mark starts like a UTF-16 one, and reads as that, followed by a NUL.)
    private static func utf8Bytes(of data: Data) throws -> [UInt8] {
        let bytes = Array(data)
        let encoding: String.Encoding
        var start = 0
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            (encoding, start) = (.utf32BigEndian, 4)
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            (encoding, start) = (.utf16BigEndian, 2)
        } else if bytes.starts(with: [0xFF, 0xFE]) {
            (encoding, start) = (.utf16LittleEndian, 2)
        } else if bytes.count > 4 {
            switch (bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 0) {
            case (true, true, true, false):
                encoding = .utf32BigEndian
            case (false, true, true, true):
                encoding = .utf32LittleEndian
            case (true, false, true, false):
                encoding = .utf16BigEndian
            case (false, true, false, true):
                encoding = .utf16LittleEndian
            default:
                return bytes
            }
        } else {
            return bytes
        }
        guard let text = String(bytes: bytes[start...], encoding: encoding) else {
            throw JSONTextError(message: "Invalid UTF-16 or UTF-32 text", offset: start)
        }
        return Array(text.utf8)
    }

    private let bytes: [UInt8]
    private var index = 0

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private mutating func parseValue(depth: Int) throws -> JSONValue {
        skipWhitespace()
        switch try next() {
        case UInt8(ascii: "["):
            return try parseArray(depth: depth)
        case UInt8(ascii: "{"):
            return try parseObject(depth: depth)
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"):
            try literal("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try literal("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try literal("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return try parseNumber()
        default:
            throw failure("Unexpected character")
        }
    }

    private mutating func parseArray(depth: Int) throws -> JSONValue {
        index += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if try next() == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        try checkDepth(depth)
        repeat {
            items.append(try parseValue(depth: depth + 1))
        } while try hasAnotherMember(closing: UInt8(ascii: "]"))
        return .array(items)
    }

    private mutating func parseObject(depth: Int) throws -> JSONValue {
        index += 1
        var members: [String: JSONValue] = [:]
        skipWhitespace()
        if try next() == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        try checkDepth(depth)
        repeat {
            skipWhitespace()
            guard try next() == UInt8(ascii: "\"") else { throw failure("Expected a string key") }
            let key = try parseString()
            skipWhitespace()
            guard try next() == UInt8(ascii: ":") else { throw failure("Expected ':' after a key") }
            index += 1
            let value = try parseValue(depth: depth + 1)
            if members[key] == nil {
                members[key] = value
            }
        } while try hasAnotherMember(closing: UInt8(ascii: "}"))
        return .object(members)
    }

    private func checkDepth(_ depth: Int) throws {
        guard depth < Self.maximumDepth else { throw failure("Nested deeper than \(Self.maximumDepth) levels") }
    }

    /// After a member: true when a comma and another member follow, false when the container
    /// closes, directly or after a trailing comma.
    private mutating func hasAnotherMember(closing: UInt8) throws -> Bool {
        skipWhitespace()
        let byte = try next()
        index += 1
        if byte == closing {
            return false
        }
        guard byte == UInt8(ascii: ",") else {
            index -= 1
            throw failure("Expected ',' or '\(Character(Unicode.Scalar(closing)))'")
        }
        skipWhitespace()
        if try next() == closing {
            index += 1
            return false
        }
        return true
    }

    private mutating func literal(_ word: String) throws {
        let expected = Array(word.utf8)
        guard bytes[index...].starts(with: expected) else { throw failure("Unexpected character") }
        index += expected.count
    }

    // MARK: Strings

    private mutating func parseString() throws -> String {
        let quote = index
        index += 1
        var utf8: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                // Decoding replaces each invalid sequence, so the bytes come back only when valid.
                let text = String(decoding: utf8, as: UTF8.self)
                guard text.utf8.elementsEqual(utf8) else {
                    throw JSONTextError(message: "Invalid UTF-8 in a string", offset: quote)
                }
                return text
            case UInt8(ascii: "\\"):
                try appendEscape(to: &utf8)
            case 0..<0x20:
                throw failure("Unescaped control character in a string")
            default:
                utf8.append(byte)
                index += 1
            }
        }
        throw JSONTextError(message: "Unterminated string", offset: quote)
    }

    private mutating func appendEscape(to utf8: inout [UInt8]) throws {
        let backslash = index
        index += 1
        let byte = try next()
        index += 1
        switch byte {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"):
            utf8.append(byte)
        case UInt8(ascii: "b"):
            utf8.append(0x08)
        case UInt8(ascii: "f"):
            utf8.append(0x0C)
        case UInt8(ascii: "n"):
            utf8.append(0x0A)
        case UInt8(ascii: "r"):
            utf8.append(0x0D)
        case UInt8(ascii: "t"):
            utf8.append(0x09)
        case UInt8(ascii: "u"):
            utf8.append(contentsOf: try unicodeEscape(at: backslash).utf8)
        default:
            throw JSONTextError(message: "Invalid escape in a string", offset: backslash)
        }
    }

    /// The scalar of a \uXXXX escape whose "\u" is already read, with the second half of a
    /// surrogate pair when the first is a high surrogate. A lone surrogate is refused.
    private mutating func unicodeEscape(at backslash: Int) throws -> Unicode.Scalar {
        let unpaired = JSONTextError(message: "Unpaired surrogate in a string", offset: backslash)
        let first = try hexQuad(at: backslash)
        if (0xDC00...0xDFFF).contains(first) {
            throw unpaired
        }
        guard (0xD800...0xDBFF).contains(first) else { return Unicode.Scalar(first)! }
        guard bytes[index...].starts(with: Array(#"\u"#.utf8)) else { throw unpaired }
        index += 2
        let second = try hexQuad(at: backslash)
        guard (0xDC00...0xDFFF).contains(second) else { throw unpaired }
        return Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))!
    }

    private mutating func hexQuad(at backslash: Int) throws -> UInt32 {
        guard index + 4 <= bytes.count,
              let value = UInt32(String(decoding: bytes[index..<(index + 4)], as: UTF8.self), radix: 16),
              bytes[index..<(index + 4)].allSatisfy({ $0 != UInt8(ascii: "+") && $0 != UInt8(ascii: "-") }) else {
            throw JSONTextError(message: "Invalid \\u escape in a string", offset: backslash)
        }
        index += 4
        return value
    }

    // MARK: Numbers

    /// -?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)?
    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        if bytes[index] == UInt8(ascii: "-") {
            index += 1
        }
        guard index < bytes.count, isDigit(bytes[index]) else { throw failure("Expected a digit") }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
            if index < bytes.count, isDigit(bytes[index]) { throw failure("Number with a leading zero") }
        } else {
            skipDigits()
        }
        var isInteger = true
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            isInteger = false
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { throw failure("Expected a digit after the decimal point") }
            skipDigits()
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            isInteger = false
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else { throw failure("Expected a digit in the exponent") }
            skipDigits()
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if isInteger, let number = Int(text) {
            return .int(number)
        }
        if isInteger, let number = UInt64(text) {
            return .int(Int(truncatingIfNeeded: number))
        }
        guard let number = Double(text), number != .infinity else {
            throw JSONTextError(message: "Number \(text) does not fit a Double", offset: start)
        }
        return .double(number)
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private mutating func skipDigits() {
        while index < bytes.count, isDigit(bytes[index]) {
            index += 1
        }
    }

    // MARK: Bytes

    /// The byte at the current position, which must exist.
    private func next() throws -> UInt8 {
        guard index < bytes.count else { throw failure("Unexpected end of text") }
        return bytes[index]
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                index += 1
            default:
                return
            }
        }
    }

    private func failure(_ message: String) -> JSONTextError {
        JSONTextError(message: message, offset: index)
    }
}
