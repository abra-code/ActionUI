// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import ActionUIVerifier

private func parse(_ text: String) throws -> JSONValue {
    try JSONTextParser.parse(Data(text.utf8))
}

@Test func parserTellsIntegersFromDoubles() throws {
    #expect(try parse("1") == .int(1))
    #expect(try parse("-7") == .int(-7))
    #expect(try parse("1.0") == .double(1))
    #expect(try parse("1e2") == .double(100))
    #expect(try parse("2.5") == .double(2.5))
    // Too large for an Int, wrapped as JSONValue(any:) wraps JSONSerialization's unsigned numbers.
    #expect(try parse("9223372036854775808") == .int(.min))
    #expect(try parse("18446744073709551615") == .int(-1))
    // Too large for a UInt64.
    #expect(try parse("18446744073709551616") == .double(18446744073709551616))
    #expect(try parse("-1e400") == .double(-.infinity))
}

@Test func parserReadsContainersAndScalars() throws {
    let value = try parse(#" {"a": [1, true, null, "x"], "b": {"c": false}, "d": [], "e": {}} "#)
    #expect(value == ["a": [1, true, nil, "x"], "b": ["c": false], "d": [], "e": [:]])
}

@Test func parserAcceptsWhatTheLoaderAccepts() throws {
    #expect(try parse("[1,2,]") == [1, 2])
    #expect(try parse(#"{"a":1,}"#) == ["a": 1])
    #expect(try parse("\u{FEFF}[1]") == [1])
    #expect(try parse(#""text""#) == "text")
    #expect(try parse(#"{"a":1,"a":2}"#) == ["a": 1])
}

@Test func parserReadsWideText() throws {
    // [1] in each encoding, with and without a byte order mark.
    let littleEndian16: [UInt8] = [0x5B, 0, 0x31, 0, 0x5D, 0]
    let bigEndian16: [UInt8] = [0, 0x5B, 0, 0x31, 0, 0x5D]
    let littleEndian32: [UInt8] = [0x5B, 0, 0, 0, 0x31, 0, 0, 0, 0x5D, 0, 0, 0]
    let bigEndian32: [UInt8] = [0, 0, 0, 0x5B, 0, 0, 0, 0x31, 0, 0, 0, 0x5D]
    for bytes in [littleEndian16, [0xFF, 0xFE] + littleEndian16, bigEndian16, [0xFE, 0xFF] + bigEndian16,
                  littleEndian32, bigEndian32, [0, 0, 0xFE, 0xFF] + bigEndian32] {
        #expect(try JSONTextParser.parse(Data(bytes)) == [1], "\(bytes)")
    }
    // A UTF-32 little-endian mark reads as a UTF-16 mark and a NUL; four bytes are too few to tell.
    for bytes in [[0xFF, 0xFE, 0, 0] + littleEndian32, [0x5B, 0, 0x5D, 0], [0xFF, 0xFE, 0x22, 0, 0x00, 0xDC, 0x22, 0]] as [[UInt8]] {
        #expect(throws: JSONTextError.self, "\(bytes)") { try JSONTextParser.parse(Data(bytes)) }
    }
}

@Test func parserReadsEscapes() throws {
    #expect(try parse(#""\"\\\/\b\f\n\r\t""#) == "\"\\/\u{8}\u{C}\n\r\t")
    #expect(try parse(#""\u00e9\u20AC""#) == "\u{E9}\u{20AC}")
    #expect(try parse(#""\ud83d\ude00""#) == "\u{1F600}")
}

@Test func parserRefusesWhatIsNotJSON() {
    let bad = ["", " ", "[", "]", "{", "}", "[1", "[1 2]", "[,]", "[1,,2]", "{1:2}", #"{"a"}"#, #"{"a":}"#, "nul", "tru", "01", "-", "1.",
               ".5", "1e", "+1", "1 2", "// x\n1", "/* x */ 1", "'a'", #"""#, #""\x""#, "\"\u{1}\"", #""\u12""#, #""\u+123""#, #""\ud83d""#,
               #""\ud83d\u0041""#, #""\ude00""#, "NaN", "Infinity", "1e999"]
    for text in bad {
        #expect(throws: JSONTextError.self, "\(text)") { try parse(text) }
    }
    #expect(throws: JSONTextError.self) { try JSONTextParser.parse(Data([0x22, 0xFF, 0x22])) }
}

/// Levels of array, what is inside them, and whether that is accepted: 512 levels with something
/// in the innermost, and an empty array one level deeper.
private let nestingCases: [(Int, String, Bool)] = [(512, "1", true), (513, "1", false), (513, "", true), (514, "", false), (512, "{}", true), (513, "{}", false)]

@Test func parserLimitsNesting() throws {
    for (count, inner, accepted) in nestingCases {
        let text = String(repeating: "[", count: count) + inner + String(repeating: "]", count: count)
        #expect(((try? parse(text)) != nil) == accepted, "\(count) levels around '\(inner)'")
    }
}

#if !os(Linux)
private func foundation(_ data: Data) -> JSONValue? {
    (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])).map { JSONValue(any: $0) }
}

/// What JSONSerialization makes of a text, which the parser stands in for on Linux.
@Test func parserMatchesFoundationOnEdgeCases() {
    let texts = ["1", "-1", "0", "-0", "0.0", "-0.0", "1.0", "1.5", "1e2", "1E2", "1e-2", "1.5e3", "100000000000", "9223372036854775807",
                 "-9223372036854775808", "[1,]", "{\"a\":1,}", "[]", "{}", "null", "true", "false", "\"x\"", "\"\\u0000\"", "\"\\/\"",
                 "{\"a\":1,\"a\":2}", "\u{FEFF}[1]", "[1,,]", "[,]", " [ 1 , 2 ] ", "\t\n\r[1]", "01", "-", "1.", ".5", "+1", "nul", "// x\n1",
                 "9223372036854775808", "18446744073709551615", "18446744073709551616", "-9223372036854775809", "1e400", "-1e400", "[-1.5e999]"]
    for text in texts {
        let data = Data(text.utf8)
        #expect((try? JSONTextParser.parse(data)) == foundation(data), "\(text)")
    }
    // Accepted or not, without foundation(): JSONValue(any:) recurses past a test thread's 512 KB here.
    for (count, inner, accepted) in nestingCases {
        let data = Data((String(repeating: "[", count: count) + inner + String(repeating: "]", count: count)).utf8)
        #expect(((try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil) == accepted, "\(count) levels around '\(inner)'")
    }
    let wide: [(String, String.Encoding, [UInt8])] = [("[1]", .utf16LittleEndian, []), ("[1]", .utf16BigEndian, []), ("[1]", .utf32LittleEndian, []),
                                                      ("[1]", .utf32BigEndian, []), ("12", .utf16LittleEndian, []), ("12", .utf32BigEndian, []),
                                                      ("12", .utf16LittleEndian, [0xFF, 0xFE]), ("12", .utf16BigEndian, [0xFE, 0xFF]),
                                                      ("12", .utf32BigEndian, [0, 0, 0xFE, 0xFF]), ("12", .utf32LittleEndian, [0xFF, 0xFE, 0, 0])]
    for (text, encoding, mark) in wide {
        let data = Data(mark) + text.data(using: encoding)!
        #expect((try? JSONTextParser.parse(data)) == foundation(data), "\(text) \(encoding) \(mark)")
    }
}

/// Every JSON document in the repository, as the verifier will meet them.
@Test func parserMatchesFoundationOnDocuments() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    var checked = 0
    for folder in ["ActionUISwiftTestApp/Resources", "ActionUIVerifier/Schemas", "Documentation", "Examples", "Add-ons", "ActionUIVerifierTests/Parity/fixtures"] {
        let root = repo.appendingPathComponent(folder)
        for relative in FileManager.default.subpaths(atPath: root.path) ?? [] where relative.hasSuffix(".json") && !relative.contains(".build/") {
            let data = try Data(contentsOf: root.appendingPathComponent(relative))
            #expect((try? JSONTextParser.parse(data)) == foundation(data), "\(folder)/\(relative)")
            checked += 1
        }
    }
    #expect(checked > 300)
}
#endif
