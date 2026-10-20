// Core/Elements/ScrollViewReaderPropsTests.swift
/*
 Tests for ScrollViewReader.Props: the id to scroll to and the anchor it is scrolled to.
*/

import XCTest
@testable import ActionUI

final class ScrollViewReaderPropsTests: XCTestCase {

    func testDefaults() {
        let props = ScrollViewReader.Props([:])
        XCTAssertNil(props.scrollTo)
        XCTAssertEqual(props.anchor, .center)
    }

    func testValidValues() {
        let props = ScrollViewReader.Props(["scrollTo": 5, "anchor": "bottom"])
        XCTAssertEqual(props.scrollTo, 5)
        XCTAssertEqual(props.anchor, .bottom)
    }

    func testEveryAnchorName() {
        for name in ["top", "center", "bottom"] {
            XCTAssertEqual(ScrollViewReader.Props(["anchor": name]).anchor.rawValue, name)
        }
    }

    func testAnchorThatIsUnknownOrNotAStringIsCenter() {
        XCTAssertEqual(ScrollViewReader.Props(["anchor": "leading"]).anchor, .center)
        XCTAssertEqual(ScrollViewReader.Props(["anchor": "Top"]).anchor, .center)
        XCTAssertEqual(ScrollViewReader.Props(["anchor": 3]).anchor, .center)
    }

    func testScrollToIsAnIntAndNothingElse() {
        XCTAssertEqual(ScrollViewReader.Props(["scrollTo": 0]).scrollTo, 0)
        XCTAssertEqual(ScrollViewReader.Props(["scrollTo": -1]).scrollTo, -1)
        XCTAssertNil(ScrollViewReader.Props(["scrollTo": 5.0]).scrollTo)
        XCTAssertNil(ScrollViewReader.Props(["scrollTo": "5"]).scrollTo)
        XCTAssertNil(ScrollViewReader.Props(["scrollTo": true]).scrollTo)
    }
}
