// Tests/Views/GeometryReaderTests.swift
/*
 GeometryReaderTests.swift

 Tests for the GeometryReader component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class GeometryReaderTests: XCTestCase {
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

    // MARK: - Property Validation

    func testValidatePropertiesValidAlignment() {
        let properties: [String: Any] = ["alignment": "center"]
        let validated = GeometryReader.validateProperties(properties, logger)
        XCTAssertEqual(validated["alignment"] as? String, "center", "Valid alignment should be preserved")
    }

    func testValidatePropertiesAllAlignments() {
        let validAlignments = ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"]
        for alignment in validAlignments {
            let properties: [String: Any] = ["alignment": alignment]
            let validated = GeometryReader.validateProperties(properties, logger)
            XCTAssertEqual(validated["alignment"] as? String, alignment, "Alignment '\(alignment)' should be valid")
        }
    }

    func testValidatePropertiesInvalidAlignment() {
        let properties: [String: Any] = ["alignment": "invalid"]
        let validated = GeometryReader.validateProperties(properties, logger)
        XCTAssertEqual(validated["alignment"] as? String, "topLeading", "Invalid alignment should default to 'topLeading'")
    }

    func testValidatePropertiesNoAlignment() {
        let properties: [String: Any] = [:]
        let validated = GeometryReader.validateProperties(properties, logger)
        XCTAssertNil(validated["alignment"], "Missing alignment should remain nil (default applied in buildView)")
    }

    // MARK: - Initial States

    func testInitialStatesSetsSizeDefault() {
        let viewModel = ViewModel()
        viewModel.states = [:]
        let states = GeometryReader.initialStates(viewModel)
        let size = states["size"] as? [Double]
        XCTAssertEqual(size, [0.0, 0.0], "Initial size should be [0.0, 0.0]")
    }

    func testInitialStatesPreservesExistingSize() {
        let viewModel = ViewModel()
        viewModel.states = ["size": [320.0, 480.0] as [Double]]
        let states = GeometryReader.initialStates(viewModel)
        let size = states["size"] as? [Double]
        XCTAssertEqual(size, [320.0, 480.0], "Existing size should be preserved")
    }

    // MARK: - View Construction

    func testConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "GeometryReader",
            "properties": [
                "alignment": "center"
            ],
            "content": [
                "type": "Text",
                "id": 10,
                "properties": ["text": "Hello"]
            ] as [String: Any]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = GeometryReader.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }

    func testConstructionWithoutContent() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "GeometryReader",
            "properties": [:] as [String: Any]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = GeometryReader.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
    }

    // MARK: - JSON Decoding

    func testJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "GeometryReader",
            "properties": {
                "alignment": "center",
                "padding": 10.0
            },
            "content": {
                "type": "Text",
                "id": 10,
                "properties": { "text": "Content inside GeometryReader" }
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "GeometryReader", "Element type should be GeometryReader")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "alignment should be 'center'")

        // Verify content subview was parsed
        let content = element.subviews?["content"] as? any ActionUIElementBase
        XCTAssertNotNil(content, "Content subview should exist")
        XCTAssertEqual(content?.id, 10, "Content element ID should be 10")
        XCTAssertEqual(content?.type, "Text", "Content element type should be Text")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        let size = viewModel.states["size"] as? [Double]
        XCTAssertEqual(size, [0.0, 0.0], "Initial size state should be [0.0, 0.0]")
    }

    func testJSONDecodingWithDefaultAlignment() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "GeometryReader",
            "properties": {},
            "content": {
                "type": "Spacer",
                "id": 10,
                "properties": {}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "GeometryReader")
        XCTAssertNil(element.properties["alignment"], "No alignment property when not specified")
    }
}
