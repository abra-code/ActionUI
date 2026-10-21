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

    func testColorPropsValid() {
        let props = ActionUI.Color.Props(["color": "blue"])
        XCTAssertEqual(props.color, "blue")
    }

    func testColorPropsIgnoreInvalidType() {
        let props = ActionUI.Color.Props(["color": 123])
        XCTAssertNil(props.color, "non-String color is ignored")
    }

    func testBuildViewWithColor() throws {
        let elementDict: [String: Any] = [
            "id": 1, "type": "Color",
            "properties": ["color": "red", "frame": ["height": 2.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Color.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Color.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewMissingColorRendersClear() throws {
        // A Color with no color string still builds (clear), warning at build time.
        let elementDict: [String: Any] = ["id": 2, "type": "Color", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        _ = ActionUI.Color.buildView(element, ViewModel(), windowUUID, properties, logger)
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
        // getElementValueType unwraps the optional, so the dispatched value type is ColorSpec.
        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: "Color")
        XCTAssertTrue(valueType == ActionUI.ColorSpec.self, "Color's value type is ColorSpec (a runtime override)")
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
        // setElementValueFromString parses a color string into a ColorSpec (valueType-driven) override.
        let json = """
        {"id": 8, "type": "Color", "properties": {"color": "blue"}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 8, value: "#00FF00")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 8)
        XCTAssertEqual(value as? ActionUI.ColorSpec, .rgba(red: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 8), "#00FF00")
    }

    // A Swift host that passes a SwiftUI Color keeps working: it is stored as its sRGB components.
    func testSetElementValueTakesASwiftUIColor() throws {
        let json = """
        {"id": 9, "type": "Color", "properties": {"color": "blue"}}
        """
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 9, value: SwiftUI.Color(red: 1, green: 0, blue: 0, opacity: 0.5))
        let stored = try XCTUnwrap(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 9) as? ActionUI.ColorSpec)
        guard case let .rgba(red, green, blue, alpha) = stored else { return XCTFail("Expected rgba, got \(stored)") }
        XCTAssertEqual(red, 1, accuracy: 0.001)
        XCTAssertEqual(green, 0, accuracy: 0.001)
        XCTAssertEqual(blue, 0, accuracy: 0.001)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.001)
    }

    // A host's named SwiftUI color stays a name, so it keeps following light and dark mode.
    func testSetElementValueKeepsANamedSwiftUIColorNamed() throws {
        let json = """
        {"id": 11, "type": "Color", "properties": {"color": "blue"}}
        """
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 11, value: SwiftUI.Color.primary)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 11) as? ActionUI.ColorSpec, .named(.primary))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 11, value: SwiftUI.Color.accentColor)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 11) as? ActionUI.ColorSpec, .named(.accentColor))
    }

    // A named color reads back as the hex SwiftUI resolves it to, as before.
    func testNamedColorValueReadsAsResolvedHex() throws {
        let json = """
        {"id": 10, "type": "Color", "properties": {"color": "blue"}}
        """
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 10, value: "red")
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 10) as? ActionUI.ColorSpec, .named(.red))
        XCTAssertEqual(ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 10), ColorHelper.colorToHex(.red))
    }
}
