// Tests/Helpers/TemplateHelperTests.swift
/*
 TemplateHelperTests.swift

 Tests for TemplateHelper column substitution logic.
*/

import XCTest
import SwiftUI
@testable import ActionUI

/// Captures logged messages so the buildTemplateView smoke tests can verify whether the registry
/// built the real view (nothing logged) or took its EmptyView fallback (logs "returning EmptyView").
/// buildTemplateView returns a type-erased AnyView, so the wrapped view type cannot be inspected directly.
private final class CapturingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var messages: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        messages.append(message)
    }
    func contains(_ substring: String) -> Bool {
        messages.contains { $0.contains(substring) }
    }
}

@MainActor
final class TemplateHelperTests: XCTestCase {

    /// Installed as the registry's shared logger in setUp so the buildTemplateView tests can observe
    /// whether construction took the EmptyView fallback. (buildTemplateView's own `logger` parameter
    /// is currently unused; the registry logs through its shared logger.) Installing it here also
    /// gives this suite the test isolation it previously lacked.
    private var capturingLogger: CapturingLogger!

    override func setUp() async throws {
        try await super.setUp()
        capturingLogger = CapturingLogger()
        ActionUIRegistry.shared.setLogger(capturingLogger)
        ActionUIModel.shared.logger = capturingLogger
    }

    override func tearDown() async throws {
        capturingLogger = nil
        try await super.tearDown()
    }

    // MARK: - substituteString

    func testSubstituteString_singleColumn() {
        let result = TemplateHelper.substituteString("Hello $1", row: ["World"])
        XCTAssertEqual(result, "Hello World")
    }

    func testSubstituteString_multipleColumns() {
        let result = TemplateHelper.substituteString("$1 scored $2 points", row: ["Alice", "42"])
        XCTAssertEqual(result, "Alice scored 42 points")
    }

    func testSubstituteString_zeroIndex_allColumnsJoined() {
        let result = TemplateHelper.substituteString("$0", row: ["star.fill", "Favorites"])
        XCTAssertEqual(result, "star.fill, Favorites")
    }

    func testSubstituteString_noTokens_unchanged() {
        let result = TemplateHelper.substituteString("No tokens here", row: ["x", "y"])
        XCTAssertEqual(result, "No tokens here")
    }

    func testSubstituteString_tokenBeyondColumns_leftAsIs() {
        // $3 when row only has 2 columns — no replacement
        let result = TemplateHelper.substituteString("$3", row: ["a", "b"])
        XCTAssertEqual(result, "$3")
    }

    func testSubstituteString_emptyRow() {
        let result = TemplateHelper.substituteString("$0 $1", row: [])
        XCTAssertEqual(result, " $1") // $0 → "" (empty join), $1 has no match
    }

    // MARK: - substituteProperties

    func testSubstituteProperties_flatDict() {
        let props: [String: Any] = ["title": "$2", "systemImage": "$1"]
        let result = TemplateHelper.substituteProperties(props, row: ["star.fill", "Favorites"])
        XCTAssertEqual(result["title"] as? String, "Favorites")
        XCTAssertEqual(result["systemImage"] as? String, "star.fill")
    }

    func testSubstituteProperties_nestedDict() {
        let props: [String: Any] = ["font": ["name": "$1", "size": 14.0]]
        let result = TemplateHelper.substituteProperties(props, row: ["Menlo"])
        let font = result["font"] as? [String: Any]
        XCTAssertEqual(font?["name"] as? String, "Menlo")
        XCTAssertEqual(font?["size"] as? Double, 14.0) // non-string unchanged
    }

    func testSubstituteProperties_nonStringValuesUnchanged() {
        let props: [String: Any] = ["opacity": 0.5, "disabled": true, "count": 3]
        let result = TemplateHelper.substituteProperties(props, row: ["ignored"])
        XCTAssertEqual(result["opacity"] as? Double, 0.5)
        XCTAssertEqual(result["disabled"] as? Bool, true)
        XCTAssertEqual(result["count"] as? Int, 3)
    }

    func testSubstituteProperties_multipleTokensInOneString() {
        let props: [String: Any] = ["text": "$1 — $2 ($3)"]
        let result = TemplateHelper.substituteProperties(props, row: ["Alice", "Engineer", "Platform"])
        XCTAssertEqual(result["text"] as? String, "Alice — Engineer (Platform)")
    }

    // MARK: - buildTemplateView (structural smoke tests)

    func testBuildStatelessView_text() {
        let element = ActionUIElement(
            id: -1, type: "Text",
            properties: ["text": "Hello $1"],
            subviews: nil
        )
        _ = TemplateHelper.buildTemplateView(
            template: element, row: ["World"],
            rowIndex: 0, parentID: 99,
            windowUUID: "test", logger: capturingLogger
        )
        XCTAssertFalse(capturingLogger.contains("returning EmptyView"), "Text template should render, not fall back to EmptyView")
    }

    func testBuildStatelessView_label() {
        let element = ActionUIElement(
            id: -1, type: "Label",
            properties: ["title": "$2", "systemImage": "$1"],
            subviews: nil
        )
        _ = TemplateHelper.buildTemplateView(
            template: element, row: ["star.fill", "Favorites"],
            rowIndex: 0, parentID: 10,
            windowUUID: "test", logger: capturingLogger
        )
        XCTAssertFalse(capturingLogger.contains("returning EmptyView"), "Label template should render, not fall back to EmptyView")
    }

    func testBuildStatelessView_unsupportedType_returnsEmptyView() {
        // Use a type with no registered construction so the registry takes its EmptyView
        // fallback (logging "returning EmptyView"). The previous "NavigationStack" is actually
        // a registered view type, so it never exercised the fallback this test is named for.
        let element = ActionUIElement(
            id: -1, type: "ThisTypeIsNotRegistered",
            properties: [:],
            subviews: nil
        )
        _ = TemplateHelper.buildTemplateView(
            template: element, row: ["x"],
            rowIndex: 0, parentID: 10,
            windowUUID: "test", logger: capturingLogger
        )
        XCTAssertTrue(capturingLogger.contains("returning EmptyView"), "Unsupported type should fall back to EmptyView")
    }

    func testBuildStatelessView_divider() {
        let element = ActionUIElement(id: -1, type: "Divider", properties: [:], subviews: nil)
        _ = TemplateHelper.buildTemplateView(
            template: element, row: [],
            rowIndex: 0, parentID: 10,
            windowUUID: "test", logger: capturingLogger
        )
        XCTAssertFalse(capturingLogger.contains("returning EmptyView"), "Divider template should render, not fall back to EmptyView")
    }
}
