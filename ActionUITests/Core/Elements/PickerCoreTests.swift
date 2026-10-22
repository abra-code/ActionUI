// Core/Elements/PickerCoreTests.swift
/*
 Tests for Picker.userSelected, what choosing an option does on every platform: it stores the tag
 as the value and fires actionID with the tag as context, only when the tag differs from the value.
*/

import XCTest
@testable import ActionUI

@MainActor
final class PickerCoreTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [(actionID: String, context: String?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.setDefaultActionHandler { [weak self] actionID, _, _, _, context in
            let tag = context as? String
            MainActor.assumeIsolated { self?.fired.append((actionID, tag)) }
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    func testChoosingStoresTheTagAndFiresWithItOncePerChange() throws {
        let json = #"{"type": "Picker", "id": 1, "properties": {"options": ["One", "Two"], "actionID": "chosen"}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = Picker.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        Picker.userSelected("2", element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? String, "2")
        XCTAssertEqual(fired.map(\.actionID), ["chosen"])
        XCTAssertEqual(fired.first?.context, "2")
        Picker.userSelected("2", element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired.count, 1, "the same tag again: no change, no action")
    }
}
