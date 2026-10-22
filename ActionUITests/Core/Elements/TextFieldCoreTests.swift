// Core/Elements/TextFieldCoreTests.swift
/*
 Tests for TextField.userEditedText and userSubmitted, what typing and submitting do on every
 platform: typing stores the text as the value and fires valueChangeActionID, only when the text
 differs; submitting fires actionID, and nothing without one.
*/

import XCTest
@testable import ActionUI

@MainActor
final class TextFieldCoreTests: XCTestCase {
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

    private func load(_ json: String) throws -> (ActionUIElement, ViewModel, TextField.Props) {
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        let props = TextField.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model))
        return (element, model, props)
    }

    func testTypingStoresTheTextAndFiresTheValueChangeOncePerChange() throws {
        let (element, model, props) = try load(#"{"type": "TextField", "id": 1, "properties": {"text": "a", "valueChangeActionID": "changed"}}"#)
        TextField.userEditedText("ab", element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(model.value as? String, "ab")
        XCTAssertEqual(fired, ["changed"])
        TextField.userEditedText("ab", element: element, model: model, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired, ["changed"], "the same text again: no change, no action")
    }

    func testSubmittingFiresTheActionAndNothingWithoutOne() throws {
        let (element, _, props) = try load(#"{"type": "TextField", "id": 1, "properties": {"actionID": "submit"}}"#)
        TextField.userSubmitted(element: element, windowUUID: windowUUID, props: props)
        XCTAssertEqual(fired, ["submit"])

        ActionUIModel.shared.windowModels[windowUUID] = nil
        let (plain, _, plainProps) = try load(#"{"type": "TextField", "id": 1}"#)
        TextField.userSubmitted(element: plain, windowUUID: windowUUID, props: plainProps)
        XCTAssertEqual(fired, ["submit"])
    }
}
