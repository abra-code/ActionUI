// Tests/Views/CircleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CircleTests: XCTestCase {
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

    func testValidatePropertiesValid() {
        let properties: [String: Any] = ["fill": "green", "stroke": "blue", "strokeLineWidth": 1.5]
        let validated = ActionUI.Circle.validateProperties(properties, logger)
        XCTAssertEqual(validated["fill"] as? String, "green")
        XCTAssertEqual(validated["stroke"] as? String, "blue")
        XCTAssertEqual(validated.cgFloat(forKey: "strokeLineWidth"), 1.5)
    }

    func testValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = ["fill": 42, "stroke": false, "strokeLineWidth": "wide"]
        let validated = ActionUI.Circle.validateProperties(properties, logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
        XCTAssertNil(validated["strokeLineWidth"])
    }

    func testValidatePropertiesMissing() {
        let validated = ActionUI.Circle.validateProperties([:], logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
    }

    func testBuildViewWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Circle",
            "properties": ["fill": "primary", "frame": ["width": 60.0, "height": 60.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Circle.validateProperties(element.properties, logger)
        let view = ActionUI.Circle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Circle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Circle",
            "properties": ["stroke": "red", "strokeLineWidth": 4.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Circle.validateProperties(element.properties, logger)
        let view = ActionUI.Circle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Circle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Circle", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Circle.validateProperties(element.properties, logger)
        let view = ActionUI.Circle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Circle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testJSONDecoding() throws {
        let json = """
        {"id": 1, "type": "Circle", "properties": {"fill": "blue", "frame": {"width": 50.0, "height": 50.0}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "Circle")
        XCTAssertEqual(element.properties["fill"] as? String, "blue")
    }
}
