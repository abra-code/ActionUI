// Core/Elements/NavigationLinkPropsTests.swift
/*
 Tests for NavigationLink.Props: the title and the id of the destination in the enclosing
 navigation container.
*/

import XCTest
@testable import ActionUI

final class NavigationLinkPropsTests: XCTestCase {

    func testDefaults() {
        let props = NavigationLink.Props([:])
        XCTAssertEqual(props.title, "Link")
        XCTAssertNil(props.destinationViewId)
    }

    func testValidValues() {
        let props = NavigationLink.Props(["title": "Go to Detail", "destinationViewId": 10])
        XCTAssertEqual(props.title, "Go to Detail")
        XCTAssertEqual(props.destinationViewId, 10)
    }

    func testEmptyTitleIsKept() {
        XCTAssertEqual(NavigationLink.Props(["title": ""]).title, "")
    }

    func testTitleThatIsNotAStringIsTheDefault() {
        XCTAssertEqual(NavigationLink.Props(["title": 5]).title, "Link")
    }

    func testDestinationViewIdIsAnIntAndNothingElse() {
        XCTAssertEqual(NavigationLink.Props(["destinationViewId": 0]).destinationViewId, 0)
        XCTAssertNil(NavigationLink.Props(["destinationViewId": 10.0]).destinationViewId)
        XCTAssertNil(NavigationLink.Props(["destinationViewId": "10"]).destinationViewId)
        XCTAssertNil(NavigationLink.Props(["destinationViewId": true]).destinationViewId)
    }
}
