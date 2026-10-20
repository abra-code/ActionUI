// Core/Elements/GeometryReaderPropsTests.swift
/*
 Tests for GeometryReader.Props: the alignment of the content. The default is topLeading, the
 alignment SwiftUI's own GeometryReader uses, and so is any name that is not one of the nine.
*/

import XCTest
@testable import ActionUI

final class GeometryReaderPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertEqual(GeometryReader.Props([:]).alignment, .topLeading)
    }

    func testEveryAlignmentName() {
        let names = ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"]
        for name in names {
            XCTAssertEqual(GeometryReader.Props(["alignment": name]).alignment.rawValue, name)
        }
    }

    func testAlignmentThatIsUnknownOrNotAStringIsTopLeading() {
        XCTAssertEqual(GeometryReader.Props(["alignment": "middle"]).alignment, .topLeading)
        XCTAssertEqual(GeometryReader.Props(["alignment": "Center"]).alignment, .topLeading)
        XCTAssertEqual(GeometryReader.Props(["alignment": ""]).alignment, .topLeading)
        XCTAssertEqual(GeometryReader.Props(["alignment": 5]).alignment, .topLeading)
    }
}
