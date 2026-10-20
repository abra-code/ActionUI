// Tests/Views/CircleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CircleTests: XCTestCase {
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

    func testCirclePropsValid() {
        let properties: [String: Any] = ["fill": "green", "stroke": "blue", "strokeLineWidth": 1.5]
        let props = ActionUI.Circle.Props(properties)
        XCTAssertEqual(props.fill, "green")
        XCTAssertEqual(props.stroke, "blue")
        XCTAssertEqual(props.strokeLineWidth, 1.5)
    }

    func testCirclePropsIgnoreInvalidTypes() {
        let properties: [String: Any] = ["fill": 42, "stroke": false, "strokeLineWidth": "wide"]
        let props = ActionUI.Circle.Props(properties)
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1.0)
    }

    func testCirclePropsMissing() {
        let props = ActionUI.Circle.Props([:])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
    }

    func testBuildViewWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Circle",
            "properties": ["fill": "primary", "frame": ["width": 60.0, "height": 60.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Circle.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Circle.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Circle",
            "properties": ["stroke": "red", "strokeLineWidth": 4.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Circle.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Circle.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Circle", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Circle.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Circle.applyModifiers(view, element, windowUUID, properties, logger)
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
