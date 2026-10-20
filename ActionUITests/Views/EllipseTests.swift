// Tests/Views/EllipseTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class EllipseTests: XCTestCase {
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

    func testEllipsePropsValid() {
        let properties: [String: Any] = ["fill": "orange", "stroke": "purple", "strokeLineWidth": 1.0]
        let props = ActionUI.Ellipse.Props(properties)
        XCTAssertEqual(props.fill, "orange")
        XCTAssertEqual(props.stroke, "purple")
        XCTAssertEqual(props.strokeLineWidth, 1.0)
    }

    func testEllipsePropsIgnoreInvalidTypes() {
        let properties: [String: Any] = ["fill": 7, "stroke": true, "strokeLineWidth": "thin"]
        let props = ActionUI.Ellipse.Props(properties)
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1.0)
    }

    func testEllipsePropsMissing() {
        let props = ActionUI.Ellipse.Props([:])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
    }

    func testBuildViewWithFill() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Ellipse",
            "properties": ["fill": "orange", "frame": ["width": 120.0, "height": 60.0]]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Ellipse.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Ellipse.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewWithStroke() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "Ellipse",
            "properties": ["stroke": "blue", "strokeLineWidth": 2.5]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Ellipse.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Ellipse.applyModifiers(view, element, windowUUID, properties, logger)
    }

    func testBuildViewBare() throws {
        let elementDict: [String: Any] = ["id": 3, "type": "Ellipse", "properties": [:]]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let view = ActionUI.Ellipse.buildView(element, ViewModel(), windowUUID, properties, logger)
        _ = ActionUI.Ellipse.applyModifiers(view, element, windowUUID, properties, logger)
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
