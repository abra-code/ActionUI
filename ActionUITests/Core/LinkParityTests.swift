// Core/LinkParityTests.swift
/*
 The Swift side of the Link URL parity cases (FormatParity/link-url-cases.json at the repository
 root): each case's expected kind is "none" (nothing is shown), "relative" (shown, opens nothing) or
 "absolute" (handed to the system). On a Mac, URL(string:), which the Apple renderer uses, gives
 each; on every platform Link.destination, which the GTK renderer uses, gives each. Android
 (LinkTest.kt) and the web (link.test.mjs) check the same file.

 With ACTIONUI_FORMAT_RECORD=1 in the environment the test writes the kinds URL(string:) gives
 instead: Foundation on a Mac is the reference (Linux's Foundation parses some differently), so
 record there and look at the changes before committing.
*/

import XCTest
@testable import ActionUI

struct LinkParityCases: Codable {
    struct Case: Codable {
        var url: String
        var expected: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(url, forKey: .url)
            try container.encode(expected, forKey: .expected)
        }
    }

    var cases: [Case]
}

final class LinkParityTests: XCTestCase {
    /// FormatParity/link-url-cases.json: this file is ActionUITests/Core/LinkParityTests.swift.
    private static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("FormatParity").appendingPathComponent("link-url-cases.json")

    private static func kind(_ destination: Link.Destination) -> String {
        switch destination {
        case .none: return "none"
        case .relative: return "relative"
        case .absolute: return "absolute"
        }
    }

    private static func cases() throws -> LinkParityCases {
        try JSONDecoder().decode(LinkParityCases.self, from: Data(contentsOf: file))
    }

    func testLinkDestinationGivesEveryCasesKind() throws {
        for item in try Self.cases().cases {
            XCTAssertEqual(Self.kind(Link.destination(item.url)), item.expected, item.url.debugDescription)
        }
    }

    #if canImport(Darwin)
    /// What the Apple renderer shows: no URL, a URL without a scheme, or one with a scheme.
    private static func foundationKind(_ text: String) -> String {
        guard let url = URL(string: text) else { return "none" }
        return (url.scheme ?? "").isEmpty ? "relative" : "absolute"
    }

    func testFoundationGivesEveryCasesKind() throws {
        var file = try Self.cases()
        let record = ProcessInfo.processInfo.environment["ACTIONUI_FORMAT_RECORD"] == "1"
        for index in file.cases.indices {
            let item = file.cases[index]
            let kind = Self.foundationKind(item.url)
            if record {
                file.cases[index].expected = kind
            } else {
                XCTAssertEqual(kind, item.expected, item.url.debugDescription)
            }
        }
        if record {
            let encoder = JSONEncoder()
            // Sorted keys: without them the key order changes from one recording to the next.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try (encoder.encode(file) + Data("\n".utf8)).write(to: Self.file)
        }
    }
    #endif

    func testNoURLIsNone() {
        XCTAssertEqual(Link.destination(nil), .none)
    }
}
