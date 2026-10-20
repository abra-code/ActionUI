/*
 StepperTests.swift

 Tests for the Stepper component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class StepperTests: XCTestCase {
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

    func testStepperJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Stepper",
            "properties": {
                "value": 5.0,
                "range": {"min": 0.0, "max": 10.0},
                "step": 1.0,
                "label": "Quantity"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "Stepper")
        XCTAssertEqual(element.properties.double(forKey: "value"), 5.0)
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "min"), 0.0)
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "max"), 10.0)
        XCTAssertEqual(element.properties.double(forKey: "step"), 1.0)
        XCTAssertEqual(element.properties["label"] as? String, "Quantity")
        XCTAssertNil(element.subviews?["children"])
    }

    func testStepperJSONDecodingWithIntValues() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Stepper",
            "properties": {
                "value": 5,
                "range": {"min": 0, "max": 10},
                "step": 1
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.properties.double(forKey: "value"), 5.0)
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "min"), 0.0)
        XCTAssertEqual((element.properties["range"] as? [String: Any])?.double(forKey: "max"), 10.0)
        XCTAssertEqual(element.properties.double(forKey: "step"), 1.0)
    }

    func testStepperPropsValid() {
        let properties: [String: Any] = [
            "value": 5.0,
            "range": ["min": 0.0, "max": 10.0],
            "step": 1.0,
            "label": "Count",
            "labelFormat": "Count: %.0f"
        ]

        let props = Stepper.Props(properties)

        XCTAssertEqual(props.initialValue, 5.0)
        XCTAssertEqual(props.range?.lowerBound, 0.0)
        XCTAssertEqual(props.range?.upperBound, 10.0)
        XCTAssertEqual(props.step, 1.0)
        XCTAssertEqual(props.label, "Count")
        XCTAssertEqual(props.labelFormat, "Count: %.0f")
    }

    func testStepperLabelFormatInvalidType() {
        let properties: [String: Any] = [
            "labelFormat": 42
        ]

        let props = Stepper.Props(properties)

        XCTAssertNil(props.labelFormat, "Non-string labelFormat should be ignored")
    }

    func testStepperLabelFormatRendering() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Stepper",
            "properties": [
                "value": 5.0,
                "range": ["min": 0.0, "max": 10.0],
                "step": 1.0,
                "labelFormat": "Quantity: %.0f"
            ]
        ]

        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Verify initial value; label rendering is verified via UI tests
        XCTAssertEqual(viewModel.value as? Double, 5.0)
        XCTAssertEqual(viewModel.properties["labelFormat"] as? String, "Quantity: %.0f")
    }

    func testStepperPropsDefaults() {
        let properties: [String: Any] = [:]

        let props = Stepper.Props(properties)

        XCTAssertEqual(props.initialValue, 0.0, "Missing value should default to 0.0")
        XCTAssertNil(props.range, "Missing range should be nil")
        XCTAssertEqual(props.step, 1.0, "Missing step should default to 1.0")
    }

    func testStepperPropsInvalidValue() {
        let properties: [String: Any] = [
            "value": "bad"
        ]

        let props = Stepper.Props(properties)

        XCTAssertEqual(props.initialValue, 0.0, "Invalid value should default to 0.0")
    }

    func testStepperPropsInvalidRange() {
        let properties: [String: Any] = [
            "range": ["min": 10.0, "max": 0.0]  // min > max
        ]

        let props = Stepper.Props(properties)

        XCTAssertNil(props.range, "Invalid range (min > max) should be ignored")
    }

    func testStepperPropsInvalidStep() {
        let properties: [String: Any] = [
            "step": -1.0
        ]

        let props = Stepper.Props(properties)

        XCTAssertEqual(props.step, 1.0, "Negative step should default to 1.0")
    }

    func testStepperPropsInvalidLabel() {
        let properties: [String: Any] = [
            "label": 42
        ]

        let props = Stepper.Props(properties)

        XCTAssertEqual(props.label, "", "Non-string label should be ignored")
    }

    func testStepperViewConstructionAndBinding() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Stepper",
            "properties": [
                "value": 5.0,
                "range": ["min": 0.0, "max": 10.0],
                "step": 1.0,
                "label": "Quantity",
                "actionID": "stepper.changed"
            ]
        ]

        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body

        XCTAssertEqual(viewModel.value as? Double, 5.0, "Initial value should be 5.0")

        // Note: Binding and action triggering tests are handled in XCUITests
    }

    func testStepperViewConstructionWithoutRange() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Stepper",
            "properties": [
                "value": 3.0,
                "step": 2.0
            ]
        ]

        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body

        XCTAssertEqual(viewModel.value as? Double, 3.0, "Initial value should be 3.0")
    }
}
