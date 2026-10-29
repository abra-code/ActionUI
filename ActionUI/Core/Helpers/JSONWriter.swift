// Core/Helpers/JSONWriter.swift
/*
 JSONValue to JSON text, the same text JSONEncoder wrote for it, about seven times as fast.

 What JSONEncoder wrote, and this writes: no spaces; a Double as its shortest text without a
 trailing ".0" (2, 0.1, 1e-07, 1e+21); a string's quote, backslash and "/" escaped (the "/"
 unless asked not to), \b \t \n \f \r for those controls, \u00xx for the other controls, and
 everything else as it is; keys in UTF-8 byte order when sorted, else in the dictionary's. Byte
 order, not Swift's String `<`, which compares the composed form: the two differ for a key
 written decomposed, such as "e" followed by a combining accent.
*/

/// A Double JSON cannot hold: NaN or an infinity.
struct JSONWriteError: Error, CustomStringConvertible {
    let value: Double

    var description: String { "JSON has no number \(value)" }
}

struct JSONWriter {
    private static let hexDigits = Array("0123456789abcdef".utf8)

    private let sortedKeys: Bool
    private let escapingSlashes: Bool
    private var output: [UInt8] = []

    static func text(of value: JSONValue, sortedKeys: Bool, escapingSlashes: Bool) throws -> String {
        var writer = JSONWriter(sortedKeys: sortedKeys, escapingSlashes: escapingSlashes)
        try writer.write(value)
        return String(decoding: writer.output, as: UTF8.self)
    }

    private init(sortedKeys: Bool, escapingSlashes: Bool) {
        self.sortedKeys = sortedKeys
        self.escapingSlashes = escapingSlashes
    }

    private mutating func write(_ value: JSONValue) throws {
        switch value {
        case .null:
            output.append(contentsOf: "null".utf8)
        case .bool(let flag):
            output.append(contentsOf: (flag ? "true" : "false").utf8)
        case .int(let number):
            output.append(contentsOf: String(number).utf8)
        case .double(let number):
            guard number.isFinite else {
                throw JSONWriteError(value: number)
            }
            let text = number.description
            output.append(contentsOf: text.hasSuffix(".0") ? text.utf8.dropLast(2) : text.utf8[...])
        case .string(let text):
            write(text)
        case .array(let items):
            output.append(UInt8(ascii: "["))
            for (position, item) in items.enumerated() {
                if position > 0 {
                    output.append(UInt8(ascii: ","))
                }
                try write(item)
            }
            output.append(UInt8(ascii: "]"))
        case .object(let members):
            output.append(UInt8(ascii: "{"))
            var first = true
            if sortedKeys {
                for (key, member) in members.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
                    try write(key, member, first: &first)
                }
            } else {
                for (key, member) in members {
                    try write(key, member, first: &first)
                }
            }
            output.append(UInt8(ascii: "}"))
        }
    }

    private mutating func write(_ key: String, _ member: JSONValue, first: inout Bool) throws {
        if !first {
            output.append(UInt8(ascii: ","))
        }
        first = false
        write(key)
        output.append(UInt8(ascii: ":"))
        try write(member)
    }

    private mutating func write(_ text: String) {
        output.append(UInt8(ascii: "\""))
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"):
                output.append(UInt8(ascii: "\\"))
                output.append(byte)
            case UInt8(ascii: "/"):
                if escapingSlashes {
                    output.append(UInt8(ascii: "\\"))
                }
                output.append(byte)
            case 0x08:
                output.append(contentsOf: #"\b"#.utf8)
            case 0x09:
                output.append(contentsOf: #"\t"#.utf8)
            case 0x0A:
                output.append(contentsOf: #"\n"#.utf8)
            case 0x0C:
                output.append(contentsOf: #"\f"#.utf8)
            case 0x0D:
                output.append(contentsOf: #"\r"#.utf8)
            case 0..<0x20:
                output.append(contentsOf: #"\u00"#.utf8)
                output.append(Self.hexDigits[Int(byte >> 4)])
                output.append(Self.hexDigits[Int(byte & 0xF)])
            default:
                output.append(byte)
            }
        }
        output.append(UInt8(ascii: "\""))
    }
}
