// Tests/Views/RoundedRectangleTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class RoundedRectangleTests: XCTestCase {
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

    func testRoundedRectanglePropsValid() {
        let properties: [String: Any] = [
            "cornerRadius": 12.0,
            "cornerStyle": "continuous",
            "fill": "blue",
            "stroke": "red",
            "strokeLineWidth": 2.0
        ]
        let props = ActionUI.RoundedRectangle.Props(properties)
        XCTAssertEqual(props.cornerRadius, 12.0)
        XCTAssertEqual(props.cornerStyle, .continuous)
        XCTAssertEqual(props.fill, "blue")
        XCTAssertEqual(props.stroke, "red")
        XCTAssertEqual(props.strokeLineWidth, 2.0)
    }

    func testRoundedRectanglePropsIgnoreInvalidCornerRadius() {
        let properties: [String: Any] = ["cornerRadius": "big", "cornerStyle": "invalid"]
        let props = ActionUI.RoundedRectangle.Props(properties)
        XCTAssertEqual(props.cornerRadius, 0.0)
        XCTAssertEqual(props.cornerStyle, .circular)
    }

    func testRoundedRectanglePropsIgnoreInvalidTypes() {
        let properties: [String: Any] = ["fill": 99, "stroke": true, "strokeLineWidth": "fat"]
        let props = ActionUI.RoundedRectangle.Props(properties)
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1.0)
    }

    func testRoundedRectanglePropsMissing() {
        let props = ActionUI.RoundedRectangle.Props([:])
        XCTAssertEqual(props.cornerRadius, 0.0)
        XCTAssertNil(props.fill)
    }

    func testBuildViewWithFillCircularStyle() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "RoundedRectangle",
            "properties": ["cornerRadius": 10.0, "cornerStyle": "circular", "fill": "tint"]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.RoundedRectangle.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.RoundedRectangle.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewWithStrokeContinuousStyle() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "RoundedRectangle",
            "properties": ["cornerRadius": 16.0, "cornerStyle": "continuous", "stroke": "gray", "strokeLineWidth": 1.0]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.RoundedRectangle.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.RoundedRectangle.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewDefaultsNoCornerRadius() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "RoundedRectangle", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.RoundedRectangle.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.RoundedRectangle.applyModifiers(view, element, windowUUID, properties, logger)
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
