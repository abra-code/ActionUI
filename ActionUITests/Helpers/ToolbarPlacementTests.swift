// Helpers/ToolbarPlacementTests.swift
/*
 Tests for ToolbarHelper.placementName: which properties a toolbar item's placement is read from,
 and how a name that is not a placement reads.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ToolbarPlacementTests: XCTestCase {

    func testCurrentPropertiesWinWhenTheyCarryAPlacement() {
        XCTAssertEqual(
            ToolbarHelper.placementName(current: ["placement": "principal"], element: ["placement": "status"]),
            "principal"
        )
    }

    func testElementPropertiesWhenTheCurrentOnesCarryNone() {
        XCTAssertEqual(ToolbarHelper.placementName(current: [:], element: ["placement": "status"]), "status")
        XCTAssertEqual(ToolbarHelper.placementName(current: nil, element: ["placement": "keyboard"]), "keyboard")
    }

    func testAnythingElseIsAutomatic() {
        XCTAssertEqual(ToolbarHelper.placementName(current: nil, element: [:]), "automatic")
        XCTAssertEqual(ToolbarHelper.placementName(current: ["placement": "sideways"], element: [:]), "automatic")
        XCTAssertEqual(ToolbarHelper.placementName(current: ["placement": 5], element: ["placement": "status"]), "automatic")
    }
}
