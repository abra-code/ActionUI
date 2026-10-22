// Core/Elements/ToggleCoreTests.swift
/*
 Tests for Toggle.userSetValue, what turning a toggle on or off does on every platform: it stores
 the state as the value and fires actionID with it as context, only when it differs from the value.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ToggleCoreTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [(actionID: String, context: Bool?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.setDefaultActionHandler { [weak self] actionID, _, _, _, context in
            let on = context as? Bool
            MainActor.assumeIsolated { self?.fired.append((actionID, on)) }
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    func testTogglingStoresTheStateAndFiresWithItOncePerChange() throws {
        let json = #"{"type": "Toggle", "id": 1, "properties": {"isOn": false, "actionID": "toggled"}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = Toggle.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        Toggle.userSetValue(true, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? Bool, true)
        XCTAssertEqual(fired.map(\.actionID), ["toggled"])
        XCTAssertEqual(fired.first?.context, true)
        Toggle.userSetValue(true, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired.count, 1, "the same state again: no change, no action")
        Toggle.userSetValue(false, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? Bool, false)
        XCTAssertEqual(fired.map(\.context), [true, false])
    }
}
