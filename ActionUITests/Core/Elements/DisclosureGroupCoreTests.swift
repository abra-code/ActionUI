// Core/Elements/DisclosureGroupCoreTests.swift
/*
 Tests for DisclosureGroup.userSetExpanded, what expanding or collapsing the group does on every
 platform: it stores the state in states["isExpanded"] and fires valueChangeActionID, only when the
 state changes.
*/

import XCTest
@testable import ActionUI

@MainActor
final class DisclosureGroupCoreTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.setDefaultActionHandler { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    func testExpandingStoresTheStateAndFiresOncePerChange() throws {
        let json = #"{"type": "DisclosureGroup", "id": 1, "properties": {"title": "Details", "valueChangeActionID": "toggled"}, "children": []}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = DisclosureGroup.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        XCTAssertEqual(model.states["isExpanded"] as? Bool, false, "starts as the isExpanded property")
        DisclosureGroup.userSetExpanded(true, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.states["isExpanded"] as? Bool, true)
        XCTAssertEqual(fired, ["toggled"])
        DisclosureGroup.userSetExpanded(true, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired.count, 1, "the same state again: no change, no action")
        DisclosureGroup.userSetExpanded(false, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.states["isExpanded"] as? Bool, false)
        XCTAssertEqual(fired.count, 2)
    }
}
