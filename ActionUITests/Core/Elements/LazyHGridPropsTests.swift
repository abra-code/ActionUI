// Core/Elements/LazyHGridPropsTests.swift
/*
 Tests for LazyHGrid.Props: spacing, alignment (top, center and bottom) and the rows definitions. Unusable rows give one flexible row; only "flexible": false definitions give none.
*/

import XCTest
@testable import ActionUI

final class LazyHGridPropsTests: XCTestCase {

    func testDefaults() {
        let props = LazyHGrid.Props([:])
        XCTAssertEqual(props.spacing, 0)
        XCTAssertEqual(props.alignment, .center)
        XCTAssertEqual(props.rows, [.flexible])
    }

    func testValidValues() {
        XCTAssertEqual(LazyHGrid.Props(["spacing": 10]).spacing, 10)
        XCTAssertEqual(LazyHGrid.Props(["spacing": 10.5]).spacing, 10.5)
        for alignment in LazyHGrid.Props.Alignment.allCases {
            XCTAssertEqual(LazyHGrid.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
        let definitions: [Any] = [["minimum": 80], ["flexible": true], ["minimum": 40.5, "flexible": true]]
        XCTAssertEqual(LazyHGrid.Props(["rows": definitions]).rows, [.fixed(80), .flexible, .fixed(40.5)])
        XCTAssertEqual(LazyHGrid.Props(["rows": [["minimum": "inf"]] as [Any]]).rows, [.fixed(.infinity)])
    }

    func testSkippedDefinitions() {
        // A definition with neither a numeric minimum nor flexible: true is skipped.
        let definitions: [Any] = [["flexible": false], ["minimum": "x"], [String: Any](), ["flexible": true], ["minimum": 50]]
        XCTAssertEqual(LazyHGrid.Props(["rows": definitions]).rows, [.flexible, .fixed(50)])
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(LazyHGrid.Props(["spacing": "10"]).spacing, 0)
        XCTAssertEqual(LazyHGrid.Props(["alignment": "leading"]).alignment, .center)
        XCTAssertEqual(LazyHGrid.Props(["alignment": 5]).alignment, .center)
        // No usable row gives one flexible row.
        XCTAssertEqual(LazyHGrid.Props(["rows": [Any]()]).rows, [.flexible])
        XCTAssertEqual(LazyHGrid.Props(["rows": [["minimum": "x"]] as [Any]]).rows, [.flexible])
        XCTAssertEqual(LazyHGrid.Props(["rows": [[String: Any]()] as [Any]]).rows, [.flexible])
        XCTAssertEqual(LazyHGrid.Props(["rows": "three"]).rows, [.flexible])
        // A list with an entry that is not a dictionary is not a list of definitions.
        XCTAssertEqual(LazyHGrid.Props(["rows": [["minimum": 80], 3] as [Any]]).rows, [.flexible])
    }

    func testOnlyFlexibleFalseGivesNoRows() {
        // Validation keeps a list whose definitions say "flexible": false, and the renderer then
        // has no rows: the grid shows nothing.
        XCTAssertEqual(LazyHGrid.Props(["rows": [["flexible": false]] as [Any]]).rows, [])
        let definitions: [Any] = [["flexible": false], ["minimum": "x"], [String: Any]()]
        XCTAssertEqual(LazyHGrid.Props(["rows": definitions]).rows, [])
    }
}
