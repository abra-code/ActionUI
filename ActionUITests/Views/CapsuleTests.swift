// Tests/Views/CapsuleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CapsuleTests: XCTestCase {
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

    func testCapsulePropsValid() {
        let properties: [String: Any] = [
            "style": "continuous",
            "fill": "blue",
            "stroke": "red",
            "strokeLineWidth": 2.0
        ]
        let props = ActionUI.Capsule.Props(properties)
        XCTAssertEqual(props.style, .continuous)
        XCTAssertEqual(props.fill, "blue")
        XCTAssertEqual(props.stroke, "red")
        XCTAssertEqual(props.strokeLineWidth, 2.0)
    }

    func testCapsulePropsIgnoreInvalidStyle() {
        let properties: [String: Any] = ["style": "rounded"]
        let props = ActionUI.Capsule.Props(properties)
        XCTAssertEqual(props.style, .circular)
    }

    func testCapsulePropsIgnoreInvalidTypes() {
        let properties: [String: Any] = ["style": 42, "fill": 0, "stroke": false, "strokeLineWidth": "thick"]
        let props = ActionUI.Capsule.Props(properties)
        XCTAssertEqual(props.style, .circular)
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1.0)
    }

    func testCapsulePropsMissing() {
        let props = ActionUI.Capsule.Props([:])
        XCTAssertEqual(props.style, .circular)
        XCTAssertNil(props.fill)
    }

    func testBuildViewContinuousWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Capsule",
            "properties": ["style": "continuous", "fill": "tint"]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Capsule.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Capsule.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewCircularWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Capsule",
            "properties": ["style": "circular", "stroke": "blue", "strokeLineWidth": 2.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Capsule.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Capsule.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Capsule", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Capsule.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Capsule.applyModifiers(view, element, windowUUID, properties, logger)
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
