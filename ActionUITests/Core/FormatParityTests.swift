// Core/FormatParityTests.swift
/*
 The Swift side of the labelFormat parity cases (FormatParity/labelformat-cases.json at the
 repository root): NumberPrintf, which the Apple and GTK renderers use, gives each case's expected
 text. Android (NumberPrintfTest.kt) and the web (number-printf.test.mjs) check the same file.

 With ACTIONUI_FORMAT_RECORD=1 in the environment the test writes the expected texts instead: the C
 library's output is the reference, so record on a Mac and look at the changes before committing.
*/

import XCTest
@testable import ActionUI

/// The labelFormat parity cases file.
struct FormatParityCases: Codable {
    /// A number, or one JSON cannot write: "inf", "-inf", "nan", "-0".
    enum Value: Codable, Equatable {
        case number(Double)
        case special(String)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else {
                self = .special(try container.decode(String.self))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let number): try container.encode(number)
            case .special(let text): try container.encode(text)
            }
        }

        var double: Double {
            switch self {
            case .number(let number): return number
            case .special("inf"): return .infinity
            case .special("-inf"): return -.infinity
            case .special("-0"): return -0.0
            case .special: return .nan
            }
        }
    }

    struct Case: Codable {
        var format: String?
        var value: Value
        var decimalSeparator: String?
        /// nil: the format is refused.
        var expected: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(format, forKey: .format)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(decimalSeparator, forKey: .decimalSeparator)
            // Written as null for a refused format, so every case says what it expects.
            try container.encode(expected, forKey: .expected)
        }
    }

    var cases: [Case]
    /// NumberPrintf.plain: what a refused format shows.
    var plain: [Case]
}

final class FormatParityTests: XCTestCase {
    /// FormatParity/labelformat-cases.json: this file is ActionUITests/Core/FormatParityTests.swift.
    private static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("FormatParity").appendingPathComponent("labelformat-cases.json")

    func testNumberPrintfGivesEveryCasesText() throws {
        var file = try JSONDecoder().decode(FormatParityCases.self, from: Data(contentsOf: Self.file))
        let record = ProcessInfo.processInfo.environment["ACTIONUI_FORMAT_RECORD"] == "1"
        for index in file.cases.indices {
            let item = file.cases[index]
            let format = try XCTUnwrap(item.format)
            let text = NumberPrintf.format(format, item.value.double, decimalSeparator: item.decimalSeparator ?? ".")
            if record {
                file.cases[index].expected = text
            } else {
                XCTAssertEqual(text, item.expected, "\(format) with \(item.value)")
            }
        }
        for index in file.plain.indices {
            let item = file.plain[index]
            let text = NumberPrintf.plain(item.value.double, decimalSeparator: item.decimalSeparator ?? ".")
            if record {
                file.plain[index].expected = text
            } else {
                XCTAssertEqual(text, item.expected, "plain \(item.value)")
            }
        }
        if record {
            let encoder = JSONEncoder()
            // Sorted keys: without them the key order changes from one recording to the next.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try (encoder.encode(file) + Data("\n".utf8)).write(to: Self.file)
        }
    }
}
