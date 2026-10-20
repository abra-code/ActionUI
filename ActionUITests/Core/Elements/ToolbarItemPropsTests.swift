// Core/Elements/ToolbarItemPropsTests.swift
/*
 Tests for ToolbarItem.Props and ToolbarItemGroup.Props: the placement. Both take the same thirteen
 names, all valid on every platform; one the platform lacks is placed as automatic by the renderer.
 A name that is not one of the thirteen, or no string, is automatic.
*/

import XCTest
@testable import ActionUI

final class ToolbarItemPropsTests: XCTestCase {

    private let names = [
        "automatic", "principal", "confirmationAction", "cancellationAction", "destructiveAction",
        "primaryAction", "secondaryAction", "topBarLeading", "topBarTrailing", "bottomBar", "keyboard",
        "navigation", "status",
    ]

    func testDefaults() {
        XCTAssertEqual(ToolbarItem.Props([:]).placement, .automatic)
        XCTAssertEqual(ToolbarItemGroup.Props([:]).placement, .automatic)
    }

    func testEveryPlacementName() {
        for name in names {
            XCTAssertEqual(ToolbarItem.Props(["placement": name]).placement.rawValue, name)
            XCTAssertEqual(ToolbarItemGroup.Props(["placement": name]).placement.rawValue, name)
        }
        XCTAssertEqual(ToolbarItem.Props.Placement.allCases.count, names.count)
    }

    func testPlacementThatIsUnknownOrNotAStringIsAutomatic() {
        for value in ["middle", "Principal", "", 5, true] as [Any] {
            XCTAssertEqual(ToolbarItem.Props(["placement": value]).placement, .automatic)
            XCTAssertEqual(ToolbarItemGroup.Props(["placement": value]).placement, .automatic)
        }
    }
}
