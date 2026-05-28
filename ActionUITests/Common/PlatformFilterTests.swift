// Common/PlatformFilterTests.swift
/*
 PlatformFilterTests

 Mirrors the Kotlin PlatformFilterTest coverage. Verifies key-suffix resolution,
 specificity precedence, recursion into nested objects and arrays, unknown-suffix
 warn-and-drop, and the documented platform token set.
*/

import XCTest
import Foundation
@testable import ActionUI

final class PlatformFilterTests: XCTestCase {

    // MARK: - Helpers

    /// Captures log messages by level for assertion in tests.
    private final class CapturingLogger: ActionUILogger, @unchecked Sendable {
        private(set) var warnings: [String] = []
        private(set) var infos: [String] = []
        func log(_ message: String, _ level: LoggerLevel) {
            switch level {
            case .warning: warnings.append(message)
            case .info, .debug, .verbose: infos.append(message)
            case .error: XCTFail("Unexpected error-level log: \(message)")
            }
        }
    }

    private func parseDict(_ json: String) throws -> Any {
        let data = json.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    /// Round-trips through JSONSerialization with `.sortedKeys` for deterministic
    /// string comparison.
    private func canonicalJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func filterJSON(_ filter: PlatformFilter, _ json: String) throws -> String {
        let parsed = try parseDict(json)
        return try canonicalJSON(filter.filter(parsed))
    }

    private var android: PlatformFilter { PlatformFilter(active: ["android"]) }
    private var ios:     PlatformFilter { PlatformFilter(active: ["ios", "apple"]) }
    private var macos:   PlatformFilter { PlatformFilter(active: ["macos", "apple"]) }

    // MARK: - Pass-through

    func testUnsuffixedKeysPassThroughUnchanged() throws {
        let input = #"{"type":"Text","properties":{"text":"hello"}}"#
        XCTAssertEqual(try filterJSON(android, input), try canonicalJSON(try parseDict(input)))
    }

    func testPrimitivesPassThroughUnchanged() throws {
        let input = "[1,2,3,\"hello\",true,null]"
        let result = try filterJSON(android, input)
        XCTAssertEqual(result, try canonicalJSON(try parseDict(input)))
    }

    // MARK: - Suffix renaming

    func testMatchingSuffixIsRenamedToBase() throws {
        XCTAssertEqual(
            try filterJSON(android, #"{"tint:android":"primary"}"#),
            #"{"tint":"primary"}"#
        )
    }

    func testNonMatchingKnownSuffixIsDropped() throws {
        XCTAssertEqual(try filterJSON(android, #"{"tint:ios":"blue"}"#), "{}")
    }

    func testUnsuffixedDefaultOverriddenByMatchingSuffix() throws {
        XCTAssertEqual(
            try filterJSON(android, #"{"tint":"gray","tint:android":"primary"}"#),
            #"{"tint":"primary"}"#
        )
    }

    func testUnsuffixedDefaultSurvivesWhenNoSuffixMatches() throws {
        XCTAssertEqual(
            try filterJSON(android, #"{"tint":"gray","tint:ios":"blue"}"#),
            #"{"tint":"gray"}"#
        )
    }

    // MARK: - Specificity

    func testSpecificPlatformWinsOverAppleUmbrellaOnIOS() throws {
        XCTAssertEqual(
            try filterJSON(ios, #"{"tint:apple":"systemGray","tint:ios":"systemBlue"}"#),
            #"{"tint":"systemBlue"}"#
        )
    }

    func testAppleUmbrellaMatchesOnMacOS() throws {
        XCTAssertEqual(
            try filterJSON(macos, #"{"tint:apple":"systemGray","tint:android":"primary"}"#),
            #"{"tint":"systemGray"}"#
        )
    }

    func testAppleUmbrellaDoesNotMatchOnAndroid() throws {
        XCTAssertEqual(
            try filterJSON(android, #"{"tint:apple":"systemGray","tint:android":"primary"}"#),
            #"{"tint":"primary"}"#
        )
    }

    func testTvOSResolvesAppleUmbrellaWhenOnlyAppleVariantExists() throws {
        let tvos = PlatformFilter(active: ["tvos", "apple"])
        XCTAssertEqual(
            try filterJSON(tvos, #"{"label:apple":"AppleLabel"}"#),
            #"{"label":"AppleLabel"}"#
        )
    }

    // MARK: - Element-level

    func testTypeLevelPlatformSwitchPicksMatchingVariant() throws {
        XCTAssertEqual(
            try filterJSON(android, #"{"type:ios":"Button","type:android":"FilledTonalButton"}"#),
            #"{"type":"FilledTonalButton"}"#
        )
    }

    func testElementWithOnlyNonMatchingTypeVariantsHasNoType() throws {
        let result = try filterJSON(android, #"{"type:ios":"Picker","properties":{"title":"x"}}"#)
        XCTAssertFalse(result.contains("\"type\""), "Expected no type key, got: \(result)")
        XCTAssertTrue(result.contains("\"properties\""), "Expected properties to survive: \(result)")
    }

    // MARK: - Unknown suffix → warn + drop

    func testUnknownSuffixIsDroppedWithWarning() throws {
        let logger = CapturingLogger()
        let filter = PlatformFilter(active: ["android"], logger: logger)
        let parsed = try parseDict(#"{"time:format":"HH:mm"}"#)
        let result = try canonicalJSON(filter.filter(parsed))
        XCTAssertEqual(result, "{}")
        XCTAssertEqual(logger.warnings.count, 1)
        let msg = logger.warnings[0]
        XCTAssertTrue(msg.contains("Unknown platform suffix"))
        XCTAssertTrue(msg.contains("'time:format'"))
        XCTAssertTrue(msg.contains("suffix='format'"))
    }

    func testTypoInPlatformTokenLogsWarningAndDropsKey() throws {
        let logger = CapturingLogger()
        let filter = PlatformFilter(active: ["android"], logger: logger)
        let parsed = try parseDict(#"{"tint:Android":"primary","tint":"gray"}"#)
        let result = try canonicalJSON(filter.filter(parsed))
        XCTAssertEqual(result, #"{"tint":"gray"}"#)
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("'tint:Android'"))
    }

    func testEmptySuffixIsTreatedAsUnknownAndWarned() throws {
        let logger = CapturingLogger()
        let filter = PlatformFilter(active: ["android"], logger: logger)
        let parsed = try parseDict(#"{"x:":"value"}"#)
        let result = try canonicalJSON(filter.filter(parsed))
        XCTAssertEqual(result, "{}")
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("suffix=''"))
    }

    func testKnownButInactivePlatformDoesNotProduceWarning() throws {
        let logger = CapturingLogger()
        let filter = PlatformFilter(active: ["android"], logger: logger)
        _ = filter.filter(try parseDict(#"{"tint:ios":"blue"}"#))
        XCTAssertTrue(logger.warnings.isEmpty, "Expected no warnings, got: \(logger.warnings)")
    }

    func testMultipleUnknownSuffixesEachProduceOneWarning() throws {
        let logger = CapturingLogger()
        let filter = PlatformFilter(active: ["android"], logger: logger)
        _ = filter.filter(try parseDict(#"{"a:foo":1,"b:bar":2,"c:android":3}"#))
        XCTAssertEqual(logger.warnings.count, 2)
    }

    // MARK: - Recursion

    func testFilterRecursesIntoNestedObjects() throws {
        XCTAssertEqual(
            try filterJSON(
                android,
                #"{"properties":{"tint:android":"primary","tint:ios":"blue"}}"#
            ),
            #"{"properties":{"tint":"primary"}}"#
        )
    }

    func testFilterRecursesIntoArrays() throws {
        // Child element with only :ios type ends up as {} on Android — the
        // renderer's empty-type guard skips it. Filter does not drop array entries.
        let input = #"{"children":[{"type":"Text"},{"type:ios":"Button"}]}"#
        XCTAssertEqual(
            try filterJSON(android, input),
            #"{"children":[{"type":"Text"},{}]}"#
        )
    }

    func testNestedPlatformSuffixesDeepInTreeResolveIndependently() throws {
        let input = """
        {
          "type:android": "HStack",
          "type:ios": "VStack",
          "children": [
            {
              "type": "Text",
              "properties": {
                "text:android": "A",
                "text:ios": "I"
              }
            }
          ]
        }
        """
        XCTAssertEqual(
            try filterJSON(android, input),
            #"{"children":[{"properties":{"text":"A"},"type":"Text"}],"type":"HStack"}"#
        )
    }

    // MARK: - Runtime convenience

    func testRuntimeActiveSetIsNonEmptyOnSupportedPlatforms() throws {
        // PlatformFilter.runtimeActiveSet is computed from compile-time platform
        // flags; on any platform the tests can run on (Apple), it should be non-empty.
        XCTAssertFalse(
            PlatformFilter.runtimeActiveSet.isEmpty,
            "runtimeActiveSet must be non-empty on a supported Apple platform"
        )
    }

    func testFilterWithRuntimeActiveSetAndLoggerCapturesWarnings() throws {
        let logger = CapturingLogger()
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: logger)
        // Trigger a warning so we verify the logger is actually wired in.
        _ = filter.filter(try parseDict(#"{"x:bogus":1}"#))
        XCTAssertEqual(logger.warnings.count, 1)
    }

    // MARK: - Token table

    func testAllPlatformsSetCoversDocumentedTokens() {
        let expected: Set<String> = [
            "ios", "macos", "tvos", "watchos", "visionos", "apple",
            "android", "androidtv", "wear",
            "desktop", "web"
        ]
        XCTAssertEqual(PlatformFilter.allPlatforms, expected)
    }
}
