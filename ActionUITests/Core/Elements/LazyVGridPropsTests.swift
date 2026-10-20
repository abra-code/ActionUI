// Core/Elements/LazyVGridPropsTests.swift
/*
 Tests for LazyVGrid.Props: spacing, alignment (leading, center and trailing) and the columns definitions. Unusable columns give one flexible column; only "flexible": false definitions give none.
*/

import XCTest
@testable import ActionUI

final class LazyVGridPropsTests: XCTestCase {

    func testDefaults() {
        let props = LazyVGrid.Props([:])
        XCTAssertEqual(props.spacing, 0)
        XCTAssertEqual(props.alignment, .center)
        XCTAssertEqual(props.columns, [.flexible])
    }

    func testValidValues() {
        XCTAssertEqual(LazyVGrid.Props(["spacing": 10]).spacing, 10)
        XCTAssertEqual(LazyVGrid.Props(["spacing": 10.5]).spacing, 10.5)
        for alignment in LazyVGrid.Props.Alignment.allCases {
            XCTAssertEqual(LazyVGrid.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
        let definitions: [Any] = [["minimum": 80], ["flexible": true], ["minimum": 40.5, "flexible": true]]
        XCTAssertEqual(LazyVGrid.Props(["columns": definitions]).columns, [.fixed(80), .flexible, .fixed(40.5)])
        XCTAssertEqual(LazyVGrid.Props(["columns": [["minimum": "inf"]] as [Any]]).columns, [.fixed(.infinity)])
    }

    func testSkippedDefinitions() {
        // A definition with neither a numeric minimum nor flexible: true is skipped.
        let definitions: [Any] = [["flexible": false], ["minimum": "x"], [String: Any](), ["flexible": true], ["minimum": 50]]
        XCTAssertEqual(LazyVGrid.Props(["columns": definitions]).columns, [.flexible, .fixed(50)])
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(LazyVGrid.Props(["spacing": "10"]).spacing, 0)
        XCTAssertEqual(LazyVGrid.Props(["alignment": "top"]).alignment, .center)
        XCTAssertEqual(LazyVGrid.Props(["alignment": 5]).alignment, .center)
        // No usable column gives one flexible column.
        XCTAssertEqual(LazyVGrid.Props(["columns": [Any]()]).columns, [.flexible])
        XCTAssertEqual(LazyVGrid.Props(["columns": [["minimum": "x"]] as [Any]]).columns, [.flexible])
        XCTAssertEqual(LazyVGrid.Props(["columns": [[String: Any]()] as [Any]]).columns, [.flexible])
        XCTAssertEqual(LazyVGrid.Props(["columns": "three"]).columns, [.flexible])
        // A list with an entry that is not a dictionary is not a list of definitions.
        XCTAssertEqual(LazyVGrid.Props(["columns": [["minimum": 80], 3] as [Any]]).columns, [.flexible])
    }

    func testOnlyFlexibleFalseGivesNoColumns() {
        // Validation keeps a list whose definitions say "flexible": false, and the renderer then
        // has no columns: the grid shows nothing.
        XCTAssertEqual(LazyVGrid.Props(["columns": [["flexible": false]] as [Any]]).columns, [])
        let definitions: [Any] = [["flexible": false], ["minimum": "x"], [String: Any]()]
        XCTAssertEqual(LazyVGrid.Props(["columns": definitions]).columns, [])
    }
}
