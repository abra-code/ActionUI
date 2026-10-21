// Tests/Helpers/TemplateHelperViewTests.swift
/*
 Smoke tests for TemplateHelper.buildTemplateView, the SwiftUI side: a template instance builds the
 real view through the registry. The column substitution is tested in Core/TemplateHelperTests.swift.
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
final class TemplateHelperViewTests: XCTestCase {

    /// Installed as the registry's shared logger in setUp so the buildTemplateView tests can observe
    /// whether construction took the EmptyView fallback. (buildTemplateView's own `logger` parameter
    /// is currently unused; the registry logs through its shared logger.) Installing it here also
    /// gives this suite the test isolation it previously lacked.
    private var capturingLogger: CapturingLogger!

    override func setUp() async throws {
        try await super.setUp()
        capturingLogger = CapturingLogger()
        ActionUIModel.shared.logger = capturingLogger
    }

    override func tearDown() async throws {
        capturingLogger = nil
        try await super.tearDown()
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
