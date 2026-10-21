// Core/FontSpecTests.swift
/*
 Tests for FontSpec: each form of a font property, the fallbacks, and their warnings.
*/

import XCTest
@testable import ActionUI

private final class WarningLogger: ActionUILogger, @unchecked Sendable {
    private(set) var warnings: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .warning { warnings.append(message) }
    }
}

final class FontSpecTests: XCTestCase {

    func testTextStylesAndNames() {
        let logger = WarningLogger()
        for style in FontTextStyle.allCases {
            XCTAssertEqual(FontSpec.parse(style.rawValue, logger: logger), .textStyle(style))
        }
        XCTAssertEqual(FontSpec.parse("Menlo", logger: logger), .named("Menlo"))
        XCTAssertEqual(FontSpec.parse("Body", logger: logger), .named("Body"), "Text styles are compared exactly")
        XCTAssertEqual(logger.warnings, [])
    }

    func testObjects() {
        let logger = WarningLogger()
        XCTAssertEqual(FontSpec.parse(["size": 12], logger: logger), .sized(name: nil, size: 12, weight: nil, design: .default))
        XCTAssertEqual(FontSpec.parse(["name": "Menlo", "size": 13.5, "weight": "bold"] as [String: Any], logger: logger),
                       .sized(name: "Menlo", size: 13.5, weight: .bold, design: .default))
        XCTAssertEqual(FontSpec.parse(["size": 10, "design": "monospaced", "weight": "ultraLight"] as [String: Any], logger: logger),
                       .sized(name: nil, size: 10, weight: .ultraLight, design: .monospaced))
        XCTAssertEqual(logger.warnings, [])
    }

    func testFallbacksWarn() {
        let logger = WarningLogger()
        XCTAssertEqual(FontSpec.parse(nil, logger: logger), .textStyle(.body))
        XCTAssertEqual(FontSpec.parse(14, logger: logger), .textStyle(.body))
        XCTAssertEqual(FontSpec.parse(["name": "Menlo"], logger: logger), .textStyle(.body), "size is required")
        XCTAssertEqual(FontSpec.parse(["size": 12, "weight": "hefty"] as [String: Any], logger: logger),
                       .sized(name: nil, size: 12, weight: nil, design: .default))
        XCTAssertEqual(FontSpec.parse(["size": 12, "design": "gothic"] as [String: Any], logger: logger),
                       .sized(name: nil, size: 12, weight: nil, design: .default))
        XCTAssertEqual(FontSpec.parse(["name": "Menlo", "size": 12, "design": "gothic"] as [String: Any], logger: logger),
                       .sized(name: "Menlo", size: 12, weight: nil, design: .default), "A named font's design is still read, and warned about")
        XCTAssertEqual(logger.warnings, [
            "Font must be a String or Dictionary; defaulting to 'body'",
            "Font must be a String or Dictionary; defaulting to 'body'",
            "Font dictionary requires 'size'; defaulting to body",
            "Unknown font weight 'hefty'; ignoring",
            "Unknown font design 'gothic'; using default",
            "Unknown font design 'gothic'; using default",
        ])
    }

    func testCaseCounts() {
        XCTAssertEqual(FontTextStyle.allCases.count, 11)
        XCTAssertEqual(FontWeight.allCases.count, 9)
        XCTAssertEqual(FontDesign.allCases.count, 4)
    }
}
