// Core/Helpers/JSONParser.swift
/*
 JSON text to JSONValue in one pass over the bytes. It accepts what JSONDecoder accepts for
 JSONValue, which documents and adapters relied on: a trailing comma in an array or object, the
 first of a repeated key, a UTF-8 byte order mark, a bare string, number, bool or null, and nesting
 to 512 levels; every number that fits an Int without loss is `.int`, negative zero is `.double`.

 Why not JSONDecoder: JSONValue's Decodable conformance asks the decoder for each kind in turn, and
 every refusal is a thrown DecodingError, built with its coding path and description: one per
 scalar that is not a Bool and four per array or object. A 160 KB request of table rows took 20 ms
 that way where JSONSerialization took 1.5. This parser throws only for text that is not JSON.

 It keeps a stack of the containers still open instead of recursing, so a deeply nested text
 cannot overflow a small thread stack (a dispatch queue thread's 512 KB on Apple), as the
 decoder's recursion could.

 UTF-16 and UTF-32 text, which JSONDecoder also reads, is left to JSONDecoder.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Text that is not JSON: what was wrong, and the byte offset where the parser found it.
struct JSONParseError: Error, CustomStringConvertible {
    let message: String
    let offset: Int

    var description: String { "\(message) at byte \(offset)" }
}

struct JSONParser {
    /// The deepest nesting accepted, JSONDecoder's limit.
    static let maximumDepth = 512

    static func parse(_ data: Data) throws -> JSONValue {
        return try data.withUnsafeBytes { bytes in
            if isWide(bytes) {
                return try JSONDecoder().decode(JSONValue.self, from: data)
            }
            var parser = JSONParser(bytes: bytes)
            return try parser.parseText()
        }
    }

    // UTF-16 or UTF-32, by a byte order mark or a zero byte among the first two, as JSONDecoder
    // tells them apart. JSON text in UTF-8 has neither.
    private static func isWide(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard bytes.count >= 2 else { return false }
        return bytes[0] == 0 || bytes[1] == 0
            || (bytes[0] == 0xFE && bytes[1] == 0xFF) || (bytes[0] == 0xFF && bytes[1] == 0xFE)
    }

    private enum Container {
        case array
        case object
    }

    private let bytes: UnsafeRawBufferPointer
    private var index = 0

    private init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    private mutating func parseText() throws -> JSONValue {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            index = 3
        }
        // The containers still open, innermost last, with the members so far of each kind and
        // each open object's key waiting for its value. The members are changed in place
        // (arrays[last].append), never through a copy, which would copy them all at each member.
        var open: [Container] = []
        var arrays: [[JSONValue]] = []
        var objects: [[String: JSONValue]] = []
        var keys: [String] = []
        var value: JSONValue
        while true {
            // One value, or an opened container to come back to for its first member.
            skipWhitespace()
            switch try next() {
            case UInt8(ascii: "["):
                try checkDepth(open.count)
                index += 1
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                    index += 1
                    value = .array([])
                } else {
                    open.append(.array)
                    arrays.append([])
                    continue
                }
            case UInt8(ascii: "{"):
                try checkDepth(open.count)
                index += 1
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                    index += 1
                    value = .object([:])
                } else {
                    keys.append(try parseKey())
                    open.append(.object)
                    objects.append([:])
                    continue
                }
            default:
                value = try parseScalar()
            }

            // The value goes to the innermost open container; each container it completes goes
            // to the one around it, until one wants another member.
            var wantsMember = false
            while !wantsMember, let container = open.last {
                skipWhitespace()
                switch container {
                case .array:
                    arrays[arrays.count - 1].append(value)
                    if try separator(closing: UInt8(ascii: "]")) {
                        wantsMember = true
                    } else {
                        open.removeLast()
                        value = .array(arrays.removeLast())
                    }
                case .object:
                    let key = keys.removeLast()
                    if objects[objects.count - 1][key] == nil {
                        objects[objects.count - 1][key] = value
                    }
                    if try separator(closing: UInt8(ascii: "}")) {
                        keys.append(try parseKey())
                        wantsMember = true
                    } else {
                        open.removeLast()
                        value = .object(objects.removeLast())
                    }
                }
            }
            if wantsMember {
                continue
            }
            skipWhitespace()
            guard index == bytes.count else {
                throw failure("Unexpected text after the JSON value")
            }
            return value
        }
    }

    // MARK: - Structure

    private func checkDepth(_ openCount: Int) throws {
        guard openCount < Self.maximumDepth else {
            throw failure("Nested deeper than \(Self.maximumDepth) levels")
        }
    }

    // After a member: true when a comma and another member follow, false when the container
    // closes, directly or after a trailing comma.
    private mutating func separator(closing: UInt8) throws -> Bool {
        let byte = try next()
        if byte == closing {
            index += 1
            return false
        }
        guard byte == UInt8(ascii: ",") else {
            throw failure("Expected ',' or '\(Character(Unicode.Scalar(closing)))'")
        }
        index += 1
        skipWhitespace()
        if index < bytes.count, bytes[index] == closing {
            index += 1
            return false
        }
        return true
    }

    // A member's key and the colon after it.
    private mutating func parseKey() throws -> String {
        guard try next() == UInt8(ascii: "\"") else {
            throw failure("Expected a string key")
        }
        let key = try parseString()
        skipWhitespace()
        guard try next() == UInt8(ascii: ":") else {
            throw failure("Expected ':' after a key")
        }
        index += 1
        skipWhitespace()
        return key
    }

    private mutating func parseScalar() throws -> JSONValue {
        switch try next() {
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

    private mutating func literal(_ word: StaticString) throws {
        let length = word.utf8CodeUnitCount
        let matches = index + length <= bytes.count && word.withUTF8Buffer { expected in
            (0..<length).allSatisfy { bytes[index + $0] == expected[$0] }
        }
        guard matches else {
            throw failure("Unexpected character")
        }
        index += length
    }

    // MARK: - Strings

    private mutating func parseString() throws -> String {
        let quote = index
        index += 1
        let start = index
        var highBits: UInt8 = 0
        // The common case, a string with no escapes: its bytes are its text.
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                let text = try makeString(UnsafeRawBufferPointer(rebasing: bytes[start..<index]), highBits: highBits)
                index += 1
                return text
            }
            if byte == UInt8(ascii: "\\") {
                break
            }
            if byte < 0x20 {
                throw failure("Unescaped control character in a string")
            }
            highBits |= byte
            index += 1
        }
        guard index < bytes.count else {
            throw JSONParseError(message: "Unterminated string", offset: quote)
        }

        var utf8 = Array(bytes[start..<index])
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return try utf8.withUnsafeBytes { try makeString($0, highBits: highBits) }
            case UInt8(ascii: "\\"):
                try appendEscape(to: &utf8)
            case 0..<0x20:
                throw failure("Unescaped control character in a string")
            default:
                highBits |= byte
                utf8.append(byte)
                index += 1
            }
        }
        throw JSONParseError(message: "Unterminated string", offset: quote)
    }

    // ASCII needs no check; anything else must be valid UTF-8, which JSONDecoder requires too.
    // Decoding replaces each invalid sequence with U+FFFD, so the bytes come back unchanged only
    // when they were valid. (String(bytes:encoding:) would drop a byte order mark that starts the
    // string, and String(validating:as:) needs macOS 15.)
    private func makeString(_ utf8: UnsafeRawBufferPointer, highBits: UInt8) throws -> String {
        let text = String(decoding: utf8, as: UTF8.self)
        if highBits >= 0x80, !text.utf8.elementsEqual(utf8) {
            throw failure("Invalid UTF-8 in a string")
        }
        return text
    }

    private mutating func appendEscape(to utf8: inout [UInt8]) throws {
        let backslash = index
        index += 1
        guard index < bytes.count else {
            throw JSONParseError(message: "Unterminated string", offset: backslash)
        }
        let byte = bytes[index]
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
            let scalar = try unicodeEscape(at: backslash)
            utf8.append(contentsOf: scalar.utf8)
        default:
            throw JSONParseError(message: "Invalid escape in a string", offset: backslash)
        }
    }

    // The scalar of a \uXXXX escape whose "\u" is already read, with the second half of a
    // surrogate pair when the first is a high surrogate. A lone surrogate is refused.
    private mutating func unicodeEscape(at backslash: Int) throws -> Unicode.Scalar {
        let first = try hexQuad(at: backslash)
        if (0xDC00...0xDFFF).contains(first) {
            throw JSONParseError(message: "Unpaired surrogate in a string", offset: backslash)
        }
        if (0xD800...0xDBFF).contains(first) {
            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                throw JSONParseError(message: "Unpaired surrogate in a string", offset: backslash)
            }
            index += 2
            let second = try hexQuad(at: backslash)
            guard (0xDC00...0xDFFF).contains(second) else {
                throw JSONParseError(message: "Unpaired surrogate in a string", offset: backslash)
            }
            let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            return Unicode.Scalar(combined)!
        }
        return Unicode.Scalar(first)!
    }

    private mutating func hexQuad(at backslash: Int) throws -> UInt32 {
        guard index + 4 <= bytes.count else {
            throw JSONParseError(message: "Invalid \\u escape in a string", offset: backslash)
        }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                digit = byte - UInt8(ascii: "A") + 10
            default:
                throw JSONParseError(message: "Invalid \\u escape in a string", offset: backslash)
            }
            value = value << 4 | UInt32(digit)
            index += 1
        }
        return value
    }

    // MARK: - Numbers

    // -?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)?, as an Int when the value is integral and
    // fits one (1.0 and 1e2 too, as JSONDecoder gives them), else as a Double. Negative zero
    // ("-0" too) is a Double, keeping its sign.
    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        let negative = bytes[index] == UInt8(ascii: "-")
        if negative {
            index += 1
        }
        guard index < bytes.count, isDigit(bytes[index]) else {
            throw failure("Expected a digit")
        }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
            if index < bytes.count, isDigit(bytes[index]) {
                throw failure("Number with a leading zero")
            }
        } else {
            skipDigits()
        }
        let integerEnd = index
        var fractionIsZero = true
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw failure("Expected a digit after the decimal point")
            }
            while index < bytes.count, isDigit(bytes[index]) {
                fractionIsZero = fractionIsZero && bytes[index] == UInt8(ascii: "0")
                index += 1
            }
        }
        var hasExponent = false
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            hasExponent = true
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw failure("Expected a digit in the exponent")
            }
            skipDigits()
        }

        let text = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
        // No exponent and nothing but zeros after the point: the integer digits are the value,
        // exactly (9007199254740993.0 is 9007199254740993, which a Double cannot hold), or a
        // Double when they are beyond Int's range (-9223372036854775809 rounds to Int.min).
        if !hasExponent && fractionIsZero {
            let digits = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<integerEnd]), as: UTF8.self)
            if let number = Int(digits) {
                return number == 0 && negative ? .double(-0.0) : .int(number)
            }
            guard let number = Double(text), number.isFinite else {
                throw JSONParseError(message: "Number \(text) does not fit a Double", offset: start)
            }
            return .double(number)
        }
        guard let number = Double(text), number.isFinite else {
            throw JSONParseError(message: "Number \(text) does not fit a Double", offset: start)
        }
        if number == 0 {
            return negative ? .double(-0.0) : .int(0)
        }
        guard number == number.rounded(.towardZero), let integer = Int(exactly: number) else {
            return .double(number)
        }
        // From 2^53 a Double is not exact: 9007199254740993e0 must not be 9007199254740992.
        if number.magnitude < 9_007_199_254_740_992 {
            return .int(integer)
        }
        if let exact = exactInteger(start: start, integerEnd: integerEnd, end: index) {
            return .int(exact)
        }
        return .double(number)
    }

    // The integer a number's text spells exactly, its digits shifted by the exponent, or nil when
    // it has a fraction left or does not fit an Int.
    private func exactInteger(start: Int, integerEnd: Int, end: Int) -> Int? {
        var digits: [UInt8] = []
        var fractionCount = 0
        var exponent = 0
        var position = bytes[start] == UInt8(ascii: "-") ? start + 1 : start
        while position < end {
            let byte = bytes[position]
            if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
                let text = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[(position + 1)..<end]), as: UTF8.self)
                guard let value = Int(text) else { return nil }
                exponent = value
                break
            }
            if byte != UInt8(ascii: ".") {
                digits.append(byte)
                if position > integerEnd {
                    fractionCount += 1
                }
            }
            position += 1
        }
        let (shift, overflow) = exponent.subtractingReportingOverflow(fractionCount)
        guard !overflow, shift < digits.count + 20 else { return nil }
        if shift >= 0 {
            digits.append(contentsOf: repeatElement(UInt8(ascii: "0"), count: shift))
        } else {
            guard -shift <= digits.count, digits.suffix(-shift).allSatisfy({ $0 == UInt8(ascii: "0") }) else {
                return nil
            }
            digits.removeLast(-shift)
        }
        if bytes[start] == UInt8(ascii: "-") {
            digits.insert(UInt8(ascii: "-"), at: 0)
        }
        return Int(String(decoding: digits, as: UTF8.self))
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        return byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private mutating func skipDigits() {
        while index < bytes.count, isDigit(bytes[index]) {
            index += 1
        }
    }

    // MARK: - Bytes

    // The byte at the current position, which must exist.
    private func next() throws -> UInt8 {
        guard index < bytes.count else {
            throw failure("Unexpected end of text")
        }
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

    private func failure(_ message: String) -> JSONParseError {
        return JSONParseError(message: message, offset: index)
    }
}
