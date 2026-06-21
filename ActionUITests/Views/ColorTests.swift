// Tests/Views/ColorTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ColorTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
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

    func testValidatePropertiesValid() {
        let validated = ActionUI.Color.validateProperties(["color": "blue"], logger)
        XCTAssertEqual(validated["color"] as? String, "blue")
    }

    func testValidatePropertiesInvalidType() {
        let validated = ActionUI.Color.validateProperties(["color": 123], logger)
        XCTAssertNil(validated["color"], "non-String color is dropped")
    }

    func testBuildViewWithColor() throws {
        let elementDict: [String: Any] = [
            "id": 1, "type": "Color",
            "properties": ["color": "red", "frame": ["height": 2.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Color.validateProperties(element.properties, logger)
        let view = ActionUI.Color.buildView(element, ViewModel(), windowUUID, validated, logger)
        _ = ActionUI.Color.applyModifiers(view, element, windowUUID, validated, logger)
    }

    func testBuildViewMissingColorRendersClear() throws {
        // A Color with no color string still builds (clear), warning at build time.
        let elementDict: [String: Any] = ["id": 2, "type": "Color", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUI.Color.validateProperties(element.properties, logger)
        _ = ActionUI.Color.buildView(element, ViewModel(), windowUUID, validated, logger)
    }

    func testRegisteredAsColorType() throws {
        // The struct is `ActionUI.Color`; it must register under the JSON element type "Color".
        let json = """
        {"id": 1, "type": "Color", "properties": {"color": "blue.opacity(0.3)", "frame": {"height": 4.0}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertEqual(element.type, "Color")
        XCTAssertEqual(element.properties["color"] as? String, "blue.opacity(0.3)")
        // getElementValueType unwraps the optional, so the dispatched value type is SwiftUI.Color.
        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: "Color")
        XCTAssertTrue(valueType == SwiftUI.Color.self, "Color's value type is SwiftUI.Color (a runtime override)")
    }

    func testValueIsNilUntilSet() throws {
        // No runtime override yet: the value is nil and the `color` property is the displayed default.
        let json = """
        {"id": 7, "type": "Color", "properties": {"color": "red"}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        XCTAssertNil(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 7))
    }

    func testSetElementValueFromStringOverridesColor() throws {
        // setElementValueFromString parses a color string into a SwiftUI.Color (valueType-driven) override.
        let json = """
        {"id": 8, "type": "Color", "properties": {"color": "blue"}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 8, value: "#00FF00")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 8)
        XCTAssertEqual(value as? SwiftUI.Color, ColorHelper.resolveColor("#00FF00"))
    }
}
