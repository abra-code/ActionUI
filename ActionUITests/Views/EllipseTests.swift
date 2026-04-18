// Tests/Views/EllipseTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class EllipseTests: XCTestCase {
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
        let properties: [String: Any] = ["fill": "orange", "stroke": "purple", "strokeLineWidth": 1.0]
        let validated = ActionUI.Ellipse.validateProperties(properties, logger)
        XCTAssertEqual(validated["fill"] as? String, "orange")
        XCTAssertEqual(validated["stroke"] as? String, "purple")
        XCTAssertEqual(validated.cgFloat(forKey: "strokeLineWidth"), 1.0)
    }

    func testValidatePropertiesInvalidTypes() {
        let properties: [String: Any] = ["fill": 7, "stroke": true, "strokeLineWidth": "thin"]
        let validated = ActionUI.Ellipse.validateProperties(properties, logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
        XCTAssertNil(validated["strokeLineWidth"])
    }

    func testValidatePropertiesMissing() {
        let validated = ActionUI.Ellipse.validateProperties([:], logger)
        XCTAssertNil(validated["fill"])
        XCTAssertNil(validated["stroke"])
    }

    func testBuildViewWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Ellipse",
            "properties": ["fill": "orange", "frame": ["width": 120.0, "height": 60.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Ellipse.validateProperties(element.properties, logger)
        let view = ActionUI.Ellipse.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Ellipse.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Ellipse",
            "properties": ["stroke": "blue", "strokeLineWidth": 2.5]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Ellipse.validateProperties(element.properties, logger)
        let view = ActionUI.Ellipse.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Ellipse.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Ellipse", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Ellipse.validateProperties(element.properties, logger)
        let view = ActionUI.Ellipse.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Ellipse.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testJSONDecoding() throws {
        let json = """
        {"id": 1, "type": "Ellipse", "properties": {"fill": "red", "frame": {"width": 100.0, "height": 50.0}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "Ellipse")
        XCTAssertEqual(element.properties["fill"] as? String, "red")
    }
}
