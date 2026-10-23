// Core/Elements/ColorPickerCoreTests.swift
/*
 Tests for ColorPicker.userPicked, what picking a color does on every platform: it stores the color
 as the value and fires actionID, only when it differs from the value.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ColorPickerCoreTests: XCTestCase {
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

    func testPickingStoresTheColorAndFiresOncePerChange() throws {
        let json = #"{"type": "ColorPicker", "id": 1, "properties": {"selectedColor": "red", "actionID": "picked"}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = ColorPicker.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        let blue = ActionUI.ColorSpec.rgba(red: 0, green: 0, blue: 1, alpha: 1)
        ColorPicker.userPicked(blue, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? ActionUI.ColorSpec, blue)
        XCTAssertEqual(fired, ["picked"])
        ColorPicker.userPicked(blue, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired.count, 1, "the same color again: no change, no action")
        let halfGreen = ActionUI.ColorSpec.rgba(red: 0, green: 1, blue: 0, alpha: 0.5)
        ColorPicker.userPicked(halfGreen, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? ActionUI.ColorSpec, halfGreen)
        XCTAssertEqual(fired.count, 2)
    }

    func testWithoutAnActionIDPickingOnlyStoresTheColor() throws {
        let json = #"{"type": "ColorPicker", "id": 1, "properties": {}}"#
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = ColorPicker.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        let white = ActionUI.ColorSpec.rgba(red: 1, green: 1, blue: 1, alpha: 1)
        ColorPicker.userPicked(white, element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? ActionUI.ColorSpec, white)
        XCTAssertTrue(fired.isEmpty)
    }
}
