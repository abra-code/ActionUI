// Tests/Views/RoundedRectangleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class RoundedRectangleTests: XCTestCase {
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
            "cornerRadius": 12.0,
            "cornerStyle": "continuous",
            "fill": "blue",
            "stroke": "red",
            "strokeLineWidth": 2.0
        ]
        let validated = ActionUI.RoundedRectangle.validateProperties(properties, logger)
        XCTAssertEqual(validated.cgFloat(forKey: "cornerRadius"), 12.0)
        XCTAssertEqual(validated["cornerStyle"] as? String, "continuous")
        XCTAssertEqual(validated["fill"] as? String, "blue")
        XCTAssertEqual(validated["stroke"] as? String, "red")
        XCTAssertEqual(validated.cgFloat(forKey: "strokeLineWidth"), 2.0)
    }

    func testValidatePropertiesInvalidCornerRadius() {
        let properties: [String: Any] = ["cornerRadius": "big", "cornerStyle": "invalid"]
        let validated = ActionUI.RoundedRectangle.validateProperties(properties, logger)
        XCTAssertNil(validated["cornerRadius"])
        XCTAssertNil(validated["cornerStyle"])
    }

    func testValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = ["fill": 99, "stroke": true, "strokeLineWidth": "fat"]
        let validated = ActionUI.RoundedRectangle.validateProperties(properties, logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
        XCTAssertNil(validated["strokeLineWidth"])
    }

    func testValidatePropertiesMissing() {
        let validated = ActionUI.RoundedRectangle.validateProperties([:], logger)
        XCTAssertNil(validated["cornerRadius"])
        XCTAssertNil(validated["fill"])
    }

    func testBuildViewWithFillCircularStyle() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "RoundedRectangle",
            "properties": ["cornerRadius": 10.0, "cornerStyle": "circular", "fill": "tint"]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.RoundedRectangle.validateProperties(element.properties, logger)
        let view = ActionUI.RoundedRectangle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.RoundedRectangle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewWithStrokeContinuousStyle() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "RoundedRectangle",
            "properties": ["cornerRadius": 16.0, "cornerStyle": "continuous", "stroke": "gray", "strokeLineWidth": 1.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.RoundedRectangle.validateProperties(element.properties, logger)
        let view = ActionUI.RoundedRectangle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.RoundedRectangle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewDefaultsNoCornerRadius() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "RoundedRectangle", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.RoundedRectangle.validateProperties(element.properties, logger)
        let view = ActionUI.RoundedRectangle.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.RoundedRectangle.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testJSONDecoding() throws {
        let json = """
        {"id": 1, "type": "RoundedRectangle", "properties": {"cornerRadius": 8.0, "cornerStyle": "continuous", "fill": "secondary"}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "RoundedRectangle")
        XCTAssertEqual(element.properties.cgFloat(forKey: "cornerRadius"), 8.0)
        XCTAssertEqual(element.properties["cornerStyle"] as? String, "continuous")
    }
}
