// Tests/Views/RectangleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class RectangleTests: XCTestCase {
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
        let properties: [String: Any] = [
            "fill": "blue",
            "stroke": "red",
            "strokeLineWidth": 2.0
        ]
        let validated = ActionUI.Rectangle.validateProperties(properties, logger)
        XCTAssertEqual(validated["fill"] as? String, "blue")
        XCTAssertEqual(validated["stroke"] as? String, "red")
        XCTAssertEqual(validated.cgFloat(forKey: "strokeLineWidth"), 2.0)
    }

    func testValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = [
            "fill": 123,
            "stroke": true,
            "strokeLineWidth": "not-a-number"
        ]
        let validated = ActionUI.Rectangle.validateProperties(properties, logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
        XCTAssertNil(validated["strokeLineWidth"])
    }

    func testValidatePropertiesMissing() {
        let validated = ActionUI.Rectangle.validateProperties([:], logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
    }

    func testBuildViewWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Rectangle",
            "properties": ["fill": "blue", "frame": ["width": 100.0, "height": 50.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Rectangle.validateProperties(element.properties, logger)
        let view = ActionUI.Rectangle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Rectangle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Rectangle",
            "properties": ["stroke": "red", "strokeLineWidth": 3.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Rectangle.validateProperties(element.properties, logger)
        let view = ActionUI.Rectangle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Rectangle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Rectangle", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Rectangle.validateProperties(element.properties, logger)
        let view = ActionUI.Rectangle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Rectangle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testJSONDecoding() throws {
        let json = """
        {"id": 1, "type": "Rectangle", "properties": {"fill": "tint", "frame": {"width": 80.0, "height": 40.0}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "Rectangle")
        XCTAssertEqual(element.properties["fill"] as? String, "tint")
    }
}
