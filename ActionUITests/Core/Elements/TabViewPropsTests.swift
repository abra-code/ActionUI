// Core/Elements/TabViewPropsTests.swift
/*
 Tests for TabView.Props: the initially selected tab, the style and the selection action. The
 tabs' own keys (title, images, badge) belong to the Tab children and are not part of these Props.
 Every style name is valid on every platform; the renderer applies none for a style the platform
 lacks.
*/

import XCTest
@testable import ActionUI

final class TabViewPropsTests: XCTestCase {

    func testDefaults() {
        let props = TabView.Props([:])
        XCTAssertEqual(props.selection, 0)
        XCTAssertNil(props.style)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = TabView.Props(["selection": 2, "style": "sidebarAdaptable", "actionID": "tab.changed"])
        XCTAssertEqual(props.selection, 2)
        XCTAssertEqual(props.style, .sidebarAdaptable)
        XCTAssertEqual(props.actionID, "tab.changed")
    }

    func testEveryStyleName() {
        for name in ["automatic", "tabBarOnly", "sidebarAdaptable", "page", "verticalPage", "grouped"] {
            XCTAssertEqual(TabView.Props(["style": name]).style?.rawValue, name)
        }
    }

    func testUnknownStyleIsNilNotAutomatic() {
        // An unknown name applies no style, so an inherited one stays; only "automatic" applies .automatic.
        XCTAssertNil(TabView.Props(["style": "fancy"]).style)
        XCTAssertNil(TabView.Props(["style": "Page"]).style)
        XCTAssertNil(TabView.Props(["style": 5]).style)
    }

    func testSelectionIsAnIntAndNothingElse() {
        XCTAssertEqual(TabView.Props(["selection": -1]).selection, -1)
        XCTAssertEqual(TabView.Props(["selection": 1.0]).selection, 0)
        XCTAssertEqual(TabView.Props(["selection": 1.5]).selection, 0)
        XCTAssertEqual(TabView.Props(["selection": "1"]).selection, 0)
        XCTAssertEqual(TabView.Props(["selection": true]).selection, 0)
    }

    func testActionIDThatIsNotAStringIsNil() {
        XCTAssertNil(TabView.Props(["actionID": 5]).actionID)
    }
}
