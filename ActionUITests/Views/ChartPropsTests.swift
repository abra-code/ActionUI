// Tests/Views/ChartPropsTests.swift (Apple: Chart is not in Core yet)
/*
 Tests for Chart.Props: the selection action and its timing. The chart description is not in
 Props: Chart stores it cleaned (on load and when it is set), and the renderer caches the parse.
*/

import XCTest
@testable import ActionUI

final class ChartPropsTests: XCTestCase {
    func testDefaults() {
        let props = Chart.Props([:])
        XCTAssertNil(props.valueChangeActionID)
        XCTAssertEqual(props.selectionActionTiming, .settled)
    }

    func testValidValues() {
        let props = Chart.Props(["valueChangeActionID": "chart.selected", "selectionActionTiming": "continuous"])
        XCTAssertEqual(props.valueChangeActionID, "chart.selected")
        XCTAssertEqual(props.selectionActionTiming, .continuous)
        XCTAssertEqual(Chart.Props(["selectionActionTiming": "settled"]).selectionActionTiming, .settled)
    }

    func testUnknownTimingIsSettled() {
        XCTAssertEqual(Chart.Props(["selectionActionTiming": "instant"]).selectionActionTiming, .settled)
        XCTAssertEqual(Chart.Props(["selectionActionTiming": "Continuous"]).selectionActionTiming, .settled)
        XCTAssertEqual(Chart.Props(["selectionActionTiming": 5]).selectionActionTiming, .settled)
    }

    func testWrongActionTypeIsNone() {
        XCTAssertNil(Chart.Props(["valueChangeActionID": 5]).valueChangeActionID)
    }
}
