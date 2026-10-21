// Tests/Common/ActionUIModelViewTests.swift
/*
 The ActionUIModel tests that build an element's SwiftUI view (ActionUIView.body), so they stay
 Apple; the model's other tests are in Core/ActionUIModelTests.swift.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIModelViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // actionID is documented as a runtime-settable property. A view's binding fires the actionID from
    // the properties SNAPSHOT that buildView received: ActionUIView.body passes
    // ActionUIRegistry.currentProperties(...) into buildView, and the binding captures it by value.
    // So setElementProperty updates the LIVE viewModel.properties, which re-renders the view, but an
    // already-built binding keeps firing the build-time actionID until the view is rebuilt; only the
    // next rebuild's buildView sees the fresh value. This test pins that behavior so it is not changed
    // silently. (Edge case: if a binding fires before the rebuild, the stale actionID is used.)
    func testActionIDSnapshotIsStaleUntilRebuild() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Toggle",
            "properties": ["actionID": "toggle.A", "value": false]
        ]
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let viewModel = model.windowModels[windowUUID]?.viewModels[1] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Force a real build, exactly as ActionUIView.body does.
        _ = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID).body

        // The snapshot the binding captured == what buildView received == currentProperties.
        let buildTimeSnapshot = ActionUIRegistry.shared.currentProperties(element: element, model: viewModel)
        XCTAssertEqual(buildTimeSnapshot["actionID"] as? String, "toggle.A",
                       "First build should see the original actionID")

        // Update the property at runtime without rebuilding the view.
        model.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "actionID", value: "toggle.B")

        // The captured snapshot is a value copy, so an already-built binding still fires the stale actionID.
        XCTAssertEqual(buildTimeSnapshot["actionID"] as? String, "toggle.A",
                       "An already-built binding's captured snapshot stays stale until the view is rebuilt")

        // The live cache is updated...
        XCTAssertEqual(viewModel.properties["actionID"] as? String, "toggle.B",
                       "setElementProperty should update the live properties")

        // ...so the next rebuild's buildView receives the fresh actionID.
        let rebuildSnapshot = ActionUIRegistry.shared.currentProperties(element: element, model: viewModel)
        XCTAssertEqual(rebuildSnapshot["actionID"] as? String, "toggle.B",
                       "A rebuild should pick up the updated actionID")
    }

    // Same contract as testActionIDSnapshotIsStaleUntilRebuild, for the valueChangeActionID key
    // (used by Slider / Stepper / DatePicker / TextField etc.).
    func testValueChangeActionIDSnapshotIsStaleUntilRebuild() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Slider",
            "properties": [
                "valueChangeActionID": "slider.A",
                "value": 0.5,
                "range": ["min": 0.0, "max": 1.0]
            ]
        ]
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let viewModel = model.windowModels[windowUUID]?.viewModels[1] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        _ = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID).body

        let buildTimeSnapshot = ActionUIRegistry.shared.currentProperties(element: element, model: viewModel)
        XCTAssertEqual(buildTimeSnapshot["valueChangeActionID"] as? String, "slider.A",
                       "First build should see the original valueChangeActionID")

        model.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "valueChangeActionID", value: "slider.B")

        XCTAssertEqual(buildTimeSnapshot["valueChangeActionID"] as? String, "slider.A",
                       "An already-built binding's captured snapshot stays stale until the view is rebuilt")
        XCTAssertEqual(viewModel.properties["valueChangeActionID"] as? String, "slider.B",
                       "setElementProperty should update the live properties")

        let rebuildSnapshot = ActionUIRegistry.shared.currentProperties(element: element, model: viewModel)
        XCTAssertEqual(rebuildSnapshot["valueChangeActionID"] as? String, "slider.B",
                       "A rebuild should pick up the updated valueChangeActionID")
    }
}
