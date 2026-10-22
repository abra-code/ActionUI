// Core/Elements/ProgressViewCoreTests.swift
/*
 Tests for ProgressView.determinateProgress, the progress both renderers show (states["progress"],
 else the value, out of total, 1.0 when not given; none or more than the total is indeterminate),
 and for ProgressView.userTapped, which fires actionID.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ProgressViewCoreTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.setDefaultActionHandler { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    private func load(_ properties: String) throws -> (ActionUIElement, ViewModel, ProgressView.Props) {
        let json = #"{"type": "ProgressView", "id": 1, "properties": {"# + properties + "}}"
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        return (element, model, ProgressView.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model)))
    }

    func testTheProgressIsTheStateElseTheValueOutOfTheTotal() throws {
        let (_, model, props) = try load(#""value": 0.25"#)
        XCTAssertEqual(ProgressView.determinateProgress(model, props)?.value, 0.25)
        XCTAssertEqual(ProgressView.determinateProgress(model, props)?.total, 1, "no total: 1.0")
        _ = ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.75)
        XCTAssertEqual(ProgressView.determinateProgress(model, props)?.value, 0.75, "states[\"progress\"] wins")
    }

    func testNoProgressOrMoreThanTheTotalIsIndeterminate() throws {
        let (_, plain, plainProps) = try load(#""title": "Loading""#)
        XCTAssertNil(ProgressView.determinateProgress(plain, plainProps))
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let (_, over, overProps) = try load(#""value": 5, "total": 4"#)
        XCTAssertNil(ProgressView.determinateProgress(over, overProps))
    }

    func testATapFiresTheAction() throws {
        let (element, _, props) = try load(#""actionID": "tapped""#)
        ProgressView.userTapped(element: element, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired, ["tapped"])
    }
}
