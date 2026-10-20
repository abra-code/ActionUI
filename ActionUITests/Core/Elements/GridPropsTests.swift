// Core/Elements/GridPropsTests.swift
/*
 Tests for Grid.Props: the cell alignment (nine names) and the two spacings, with their defaults.
*/

import XCTest
@testable import ActionUI

final class GridPropsTests: XCTestCase {

    func testDefaults() {
        let props = Grid.Props([:])
        XCTAssertNil(props.horizontalSpacing)
        XCTAssertNil(props.verticalSpacing)
        XCTAssertEqual(props.alignment, .center)
    }

    func testValidValues() {
        let props = Grid.Props(["horizontalSpacing": 8, "verticalSpacing": 4.5])
        XCTAssertEqual(props.horizontalSpacing, 8)
        XCTAssertEqual(props.verticalSpacing, 4.5)
        for alignment in Grid.Props.Alignment.allCases {
            XCTAssertEqual(Grid.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
    }

    func testUnusableValuesFallBack() {
        let props = Grid.Props(["horizontalSpacing": "8", "verticalSpacing": true])
        XCTAssertNil(props.horizontalSpacing)
        XCTAssertNil(props.verticalSpacing)
        XCTAssertEqual(Grid.Props(["alignment": "middle"]).alignment, .center)
        XCTAssertEqual(Grid.Props(["alignment": 5]).alignment, .center)
    }
}
