// Tests/Views/LazyHGridTemplateTests.swift
/*
 LazyHGridTemplateTests.swift

 Tests for LazyHGrid data-driven template rendering: each data row set via
 setElementRows becomes one grid cell, flowing into the declared rows.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LazyHGridTemplateTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    func testLazyHGridTemplate_decodesTemplateSubview() throws {
        let json = """
        {
            "type": "LazyHGrid",
            "id": 10,
            "properties": { "rows": [ { "flexible": true }, { "flexible": true } ] },
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        let template = element.subviews?["template"] as? ActionUIElement
        XCTAssertNotNil(template, "template subview should be decoded")
        XCTAssertEqual(template?.type, "Text")
        XCTAssertEqual(template?.properties["text"] as? String, "$1")
    }

    func testLazyHGridTemplate_initializesContentState() throws {
        let json = """
        {
            "type": "LazyHGrid",
            "id": 10,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }
        let content = viewModel.states["content"] as? [[String]]
        XCTAssertNotNil(content, "states[\"content\"] should be initialized as [[String]]")
        XCTAssertTrue(content!.isEmpty, "content should start empty")
    }

    func testLazyHGridTemplate_buildsViewWithRows() throws {
        let json = """
        {
            "type": "LazyHGrid",
            "id": 10,
            "properties": { "rows": [ { "minimum": 40 }, { "flexible": true } ] },
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        viewModel.states["content"] = [["Alpha"], ["Beta"], ["Gamma"]]

        let validatedProps = LazyHGrid.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        XCTAssertFalse(view is SwiftUI.EmptyView, "Should render a LazyHGrid, not EmptyView")
    }

    func testLazyHGridTemplate_buildsViewWithNoRows() throws {
        let json = """
        {
            "type": "LazyHGrid",
            "id": 10,
            "template": { "type": "Text", "properties": { "text": "$1" } }
        }
        """
        let element = try load(json)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("viewModel not found"); return
        }

        let validatedProps = LazyHGrid.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProps
        )
        // Empty rows: the grid renders with no cells, still a LazyHGrid (not EmptyView)
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    // MARK: - Helpers

    private func load(_ jsonString: String) throws -> ActionUIElement {
        let data = Data(jsonString.utf8)
        return try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
    }
}
