// Helpers/SelectionListHelperTests.swift
/*
 Tests for SelectionListHelper.buildIDMaps: the maps between a list's child element IDs and the
 destination view IDs the children name with "destinationViewId" (an Int only).
*/

import XCTest
@testable import ActionUI

@MainActor
final class SelectionListHelperTests: XCTestCase {
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
        try await super.tearDown()
    }

    func testChildrenWithAnIntDestinationAreMappedBothWays() throws {
        let json = """
        {
            "id": 1,
            "type": "List",
            "properties": { "actionID": "row.selected" },
            "children": [
                { "id": 10, "type": "Text", "properties": { "text": "One", "destinationViewId": 100 } },
                { "id": 11, "type": "Text", "properties": { "text": "Two", "destinationViewId": "101" } },
                { "id": 12, "type": "Text", "properties": { "text": "Three" } },
                { "id": 13, "type": "Text", "properties": { "text": "Four", "destinationViewId": 103 } }
            ]
        }
        """
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let maps = SelectionListHelper.buildIDMaps(children: children, windowModel: ActionUIModel.shared.windowModels[windowUUID])

        XCTAssertEqual(maps.childToDestination, [10: 100, 13: 103])
        XCTAssertEqual(maps.destinationToChild, [100: 10, 103: 13])
    }

    func testUnfilteredPropertiesGiveTheSameMaps() throws {
        // Loading filters the properties; here the children's view models hold them as written.
        let json = """
        {
            "id": 1,
            "type": "List",
            "children": [
                { "id": 10, "type": "Text", "properties": { "text": "One" } },
                { "id": 11, "type": "Text", "properties": { "text": "Two" } }
            ]
        }
        """
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        windowModel?.viewModels[10]?.validatedProperties = ["text": "One", "destinationViewId": 100]
        windowModel?.viewModels[11]?.validatedProperties = ["text": "Two", "destinationViewId": "101"]
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let maps = SelectionListHelper.buildIDMaps(children: children, windowModel: windowModel)

        XCTAssertEqual(maps.childToDestination, [10: 100])
        XCTAssertEqual(maps.destinationToChild, [100: 10])
    }
}
