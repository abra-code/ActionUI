// Tests/Views/CapsuleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CapsuleTests: XCTestCase {
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
            "style": "continuous",
            "fill": "blue",
            "stroke": "red",
            "strokeLineWidth": 2.0
        ]
        let validated = ActionUI.Capsule.validateProperties(properties, logger)
        XCTAssertEqual(validated["style"] as? String, "continuous")
        XCTAssertEqual(validated["fill"] as? String, "blue")
        XCTAssertEqual(validated["stroke"] as? String, "red")
        XCTAssertEqual(validated.cgFloat(forKey: "strokeLineWidth"), 2.0)
    }

    func testValidatePropertiesInvalidStyle() {
        let properties: [String: Any] = ["style": "rounded"]
        let validated = ActionUI.Capsule.validateProperties(properties, logger)
        XCTAssertNil(validated["style"])
    }

    func testValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = ["style": 42, "fill": 0, "stroke": false, "strokeLineWidth": "thick"]
        let validated = ActionUI.Capsule.validateProperties(properties, logger)
        XCTAssertNil(validated["style"])
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
        XCTAssertNil(validated["strokeLineWidth"])
    }

    func testValidatePropertiesMissing() {
        let validated = ActionUI.Capsule.validateProperties([:], logger)
        XCTAssertNil(validated["style"])
        XCTAssertNil(validated["fill"])
    }

    func testBuildViewContinuousWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Capsule",
            "properties": ["style": "continuous", "fill": "tint"]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Capsule.validateProperties(element.properties, logger)
        let view = ActionUI.Capsule.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Capsule.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewCircularWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Capsule",
            "properties": ["style": "circular", "stroke": "blue", "strokeLineWidth": 2.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Capsule.validateProperties(element.properties, logger)
        let view = ActionUI.Capsule.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Capsule.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Capsule", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Capsule.validateProperties(element.properties, logger)
        let view = ActionUI.Capsule.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Capsule.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testJSONDecoding() throws {
        let json = """
        {"id": 1, "type": "Capsule", "properties": {"style": "continuous", "fill": "green"}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "Capsule")
        XCTAssertEqual(element.properties["style"] as? String, "continuous")
    }
}
