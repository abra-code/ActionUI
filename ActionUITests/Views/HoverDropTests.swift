/*
 HoverDropTests.swift

 Tests for the onHover and onDrop View modifier properties.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class HoverDropTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        super.tearDown()
    }

    // MARK: - onHoverActionID validation

    func testOnHoverActionIDValidString() {
        let properties: [String: Any] = ["onHoverActionID": "card.hovered"]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onHoverActionID"] as? String, "card.hovered")
    }

    func testOnHoverActionIDInvalidTypeDiscarded() {
        let properties: [String: Any] = ["onHoverActionID": 42]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onHoverActionID"], "Non-string onHoverActionID should be discarded")
    }

    func testOnHoverActionIDInvalidBoolDiscarded() {
        let properties: [String: Any] = ["onHoverActionID": true]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onHoverActionID"], "Bool onHoverActionID should be discarded")
    }

    // MARK: - onDropActionID validation

    func testOnDropActionIDValidString() {
        let properties: [String: Any] = ["onDropActionID": "zone.dropped"]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onDropActionID"] as? String, "zone.dropped")
    }

    func testOnDropActionIDInvalidTypeDiscarded() {
        let properties: [String: Any] = ["onDropActionID": 99]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onDropActionID"], "Non-string onDropActionID should be discarded")
    }

    // MARK: - onDropTypes validation

    func testOnDropTypesValidArray() {
        let properties: [String: Any] = [
            "onDropTypes": ["public.utf8-plain-text", "public.url"]
        ]
        let validated = View.validateProperties(properties, logger)
        let types = validated["onDropTypes"] as? [String]
        XCTAssertEqual(types, ["public.utf8-plain-text", "public.url"])
    }

    func testOnDropTypesSingleElement() {
        let properties: [String: Any] = ["onDropTypes": ["public.utf8-plain-text"]]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onDropTypes"] as? [String], ["public.utf8-plain-text"])
    }

    func testOnDropTypesEmptyArrayDiscarded() {
        let properties: [String: Any] = ["onDropTypes": [String]()]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onDropTypes"], "Empty onDropTypes should be discarded")
    }

    func testOnDropTypesNonArrayDiscarded() {
        let properties: [String: Any] = ["onDropTypes": "public.utf8-plain-text"]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onDropTypes"], "String (not array) onDropTypes should be discarded")
    }

    func testOnDropTypesNumberDiscarded() {
        let properties: [String: Any] = ["onDropTypes": 42]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onDropTypes"], "Number onDropTypes should be discarded")
    }

    // MARK: - onDropTargetedActionID validation

    func testOnDropTargetedActionIDValidString() {
        let properties: [String: Any] = ["onDropTargetedActionID": "zone.targeted"]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onDropTargetedActionID"] as? String, "zone.targeted")
    }

    func testOnDropTargetedActionIDInvalidTypeDiscarded() {
        let properties: [String: Any] = ["onDropTargetedActionID": 7]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["onDropTargetedActionID"], "Non-string onDropTargetedActionID should be discarded")
    }

    // MARK: - Combined validation

    func testAllDropPropertiesValidTogether() {
        let properties: [String: Any] = [
            "onDropActionID": "drop.received",
            "onDropTypes": ["public.utf8-plain-text"],
            "onDropTargetedActionID": "drop.targeted"
        ]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onDropActionID"] as? String, "drop.received")
        XCTAssertEqual(validated["onDropTypes"] as? [String], ["public.utf8-plain-text"])
        XCTAssertEqual(validated["onDropTargetedActionID"] as? String, "drop.targeted")
    }

    func testDropActionIDWithoutDropTypesPassesValidation() {
        // Both are independent; validation doesn't enforce co-presence.
        // The modifier application skips onDrop if onDropTypes is absent.
        let properties: [String: Any] = ["onDropActionID": "drop.received"]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onDropActionID"] as? String, "drop.received")
        XCTAssertNil(validated["onDropTypes"])
    }

    func testHoverAndDropTogetherOnSameElement() {
        let properties: [String: Any] = [
            "onHoverActionID": "card.hovered",
            "onDropActionID": "card.dropped",
            "onDropTypes": ["public.utf8-plain-text"],
            "onDropTargetedActionID": "card.targeted"
        ]
        let validated = View.validateProperties(properties, logger)
        XCTAssertEqual(validated["onHoverActionID"] as? String, "card.hovered")
        XCTAssertEqual(validated["onDropActionID"] as? String, "card.dropped")
        XCTAssertEqual(validated["onDropTypes"] as? [String], ["public.utf8-plain-text"])
        XCTAssertEqual(validated["onDropTargetedActionID"] as? String, "card.targeted")
    }

    // MARK: - JSON decoding

    func testHoverDropJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {
                "onHoverActionID": "demo.hovered",
                "onDropActionID": "demo.dropped",
                "onDropTypes": ["public.utf8-plain-text"],
                "onDropTargetedActionID": "demo.targeted"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "VStack")
        XCTAssertEqual(element.properties["onHoverActionID"] as? String, "demo.hovered")
        XCTAssertEqual(element.properties["onDropActionID"] as? String, "demo.dropped")
        XCTAssertEqual(element.properties["onDropTypes"] as? [String], ["public.utf8-plain-text"])
        XCTAssertEqual(element.properties["onDropTargetedActionID"] as? String, "demo.targeted")
    }

    func testHoverDropJSONDecodingInvalidTypes() throws {
        let jsonString = """
        {
            "id": 2,
            "type": "VStack",
            "properties": {
                "onHoverActionID": 99,
                "onDropActionID": true,
                "onDropTypes": "not-an-array",
                "onDropTargetedActionID": 0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        XCTAssertNil(element.properties["onHoverActionID"], "Invalid onHoverActionID should be discarded")
        XCTAssertNil(element.properties["onDropActionID"], "Invalid onDropActionID should be discarded")
        XCTAssertNil(element.properties["onDropTypes"], "Invalid onDropTypes should be discarded")
        XCTAssertNil(element.properties["onDropTargetedActionID"], "Invalid onDropTargetedActionID should be discarded")
    }

    // MARK: - View construction

    func testDropViewConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [
                "onDropActionID": "demo.dropped",
                "onDropTypes": ["public.utf8-plain-text"],
                "onDropTargetedActionID": "demo.targeted"
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.validatedProperties["onDropActionID"] as? String, "demo.dropped")
        XCTAssertEqual(viewModel.validatedProperties["onDropTypes"] as? [String], ["public.utf8-plain-text"])
        XCTAssertEqual(viewModel.validatedProperties["onDropTargetedActionID"] as? String, "demo.targeted")

        // Verify body can be evaluated without crashing
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body
    }

    func testHoverViewConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [
                "onHoverActionID": "card.hovered"
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.validatedProperties["onHoverActionID"] as? String, "card.hovered")

        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body
    }

    func testDropViewConstructionWithoutTargetedActionID() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": [
                "onDropActionID": "zone.dropped",
                "onDropTypes": ["public.utf8-plain-text", "public.url"]
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.validatedProperties["onDropActionID"] as? String, "zone.dropped")
        XCTAssertNil(viewModel.validatedProperties["onDropTargetedActionID"])

        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body
    }

    func testDropNotAppliedWhenTypesAbsent() throws {
        // onDropActionID present but onDropTypes absent — modifier should not crash
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [
                "onDropActionID": "zone.dropped"
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.validatedProperties["onDropTypes"])

        // Body evaluation must not crash even though no DropModifierView is applied
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body
    }
}
