// Core/Elements/SliderCoreTests.swift
/*
 Tests for Slider.userSetValue, what moving a slider does on every platform: it stores the position
 as the value and fires valueChangeActionID, only when the position is inside the range and differs
 from the value.
*/

import XCTest
@testable import ActionUI

@MainActor
final class SliderCoreTests: XCTestCase {
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

    func testMovingStoresThePositionInsideTheRangeOncePerChange() throws {
        let json = #"{"type": "Slider", "id": 1, "properties": {"range": {"min": 0, "max": 10}, "valueChangeActionID": "moved"}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = Slider.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        Slider.userSetValue(4, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? Double, 4)
        XCTAssertEqual(fired, ["moved"])
        Slider.userSetValue(4, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired, ["moved"], "the same position again: no change, no action")
        Slider.userSetValue(11, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? Double, 4, "outside the range: refused")
        XCTAssertEqual(fired, ["moved"])
    }
}
