// Core/Elements/StepperCoreTests.swift
/*
 Tests for Stepper.userSetValue, what stepping does on every platform: it stores the new value and
 fires actionID with it as context, only when it differs from the value.
*/

import XCTest
@testable import ActionUI

@MainActor
final class StepperCoreTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [(actionID: String, context: Double?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.setDefaultActionHandler { [weak self] actionID, _, _, _, context in
            let value = context as? Double
            MainActor.assumeIsolated { self?.fired.append((actionID, value)) }
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    func testSteppingStoresTheValueAndFiresWithItOncePerChange() throws {
        let json = #"{"type": "Stepper", "id": 1, "properties": {"value": 3, "actionID": "stepped"}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = Stepper.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        Stepper.userSetValue(4, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? Double, 4)
        XCTAssertEqual(fired.map(\.actionID), ["stepped"])
        XCTAssertEqual(fired.first?.context, 4)
        Stepper.userSetValue(4, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired.count, 1, "the same value again: no change, no action")
    }
}
