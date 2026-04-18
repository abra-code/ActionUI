// Tests/Views/OverlayBackgroundTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class OverlayBackgroundTests: XCTestCase {
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

    // MARK: - overlayAlignment validation

    func testOverlayAlignmentValidValues() {
        let valid = ["center", "leading", "trailing", "top", "bottom",
                     "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"]
        for value in valid {
            let result = View.validateProperties(["overlayAlignment": value], logger)
            XCTAssertEqual(result["overlayAlignment"] as? String, value,
                           "'\(value)' should be a valid overlayAlignment")
        }
    }

    func testOverlayAlignmentInvalidValue() {
        let result = View.validateProperties(["overlayAlignment": "left"], logger)
        XCTAssertEqual(result["overlayAlignment"] as? String, "center",
                       "Invalid overlayAlignment should default to 'center'")
    }

    func testOverlayAlignmentInvalidType() {
        let result = View.validateProperties(["overlayAlignment": 42], logger)
        XCTAssertNil(result["overlayAlignment"],
                     "Non-String overlayAlignment should be removed")
    }

    func testOverlayAlignmentMissing() {
        let result = View.validateProperties([:], logger)
        XCTAssertNil(result["overlayAlignment"])
    }

    // MARK: - backgroundAlignment validation

    func testBackgroundAlignmentValidValues() {
        let valid = ["center", "leading", "trailing", "top", "bottom",
                     "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"]
        for value in valid {
            let result = View.validateProperties(["backgroundAlignment": value], logger)
            XCTAssertEqual(result["backgroundAlignment"] as? String, value)
        }
    }

    func testBackgroundAlignmentInvalidValue() {
        let result = View.validateProperties(["backgroundAlignment": "right"], logger)
        XCTAssertEqual(result["backgroundAlignment"] as? String, "center")
    }

    func testBackgroundAlignmentInvalidType() {
        let result = View.validateProperties(["backgroundAlignment": true], logger)
        XCTAssertNil(result["backgroundAlignment"])
    }

    // MARK: - overlay JSON decoding

    func testOverlaySubviewJSONDecoding() throws {
        let json = """
        {
            "id": 1,
            "type": "Image",
            "properties": { "systemName": "bell.fill", "overlayAlignment": "topTrailing" },
            "overlay": {
                "id": 2,
                "type": "Circle",
                "properties": { "fill": "red", "frame": { "width": 12, "height": 12 } }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.properties["overlayAlignment"] as? String, "topTrailing")
        let overlay = try XCTUnwrap(element.subviews?["overlay"] as? ActionUIElement)
        XCTAssertEqual(overlay.id, 2)
        XCTAssertEqual(overlay.type, "Circle")
        XCTAssertEqual(overlay.properties["fill"] as? String, "red")
    }

    func testOverlaySubviewAbsent() throws {
        let json = """
        {"id": 1, "type": "Text", "properties": { "text": "Hi" }}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertNil(element.subviews?["overlay"])
    }

    // MARK: - backgroundView JSON decoding

    func testBackgroundSubviewJSONDecoding() throws {
        let json = """
        {
            "id": 1,
            "type": "Text",
            "properties": { "text": "Tag", "foregroundStyle": "white", "padding": 8 },
            "background": {
                "id": 2,
                "type": "Capsule",
                "properties": { "fill": "blue" }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        XCTAssertEqual(element.id, 1)
        let bg = try XCTUnwrap(element.subviews?["background"] as? ActionUIElement)
        XCTAssertEqual(bg.id, 2)
        XCTAssertEqual(bg.type, "Capsule")
        XCTAssertEqual(bg.properties["fill"] as? String, "blue")
    }

    func testBackgroundSubviewAbsent() throws {
        let json = """
        {"id": 1, "type": "Text", "properties": { "text": "Hi" }}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertNil(element.subviews?["background"])
    }

    // MARK: - Dictionary construction

    func testOverlayDictionaryConstruction() throws {
        let dict: [String: Any] = [
            "id": 1,
            "type": "Image",
            "properties": ["systemName": "bell.fill", "overlayAlignment": "topTrailing"],
            "overlay": ["id": 2, "type": "Circle", "properties": ["fill": "red"]] as [String: Any]
        ]
        let element = try ActionUIElement(from: dict, logger: logger)
        let overlay = try XCTUnwrap(element.subviews?["overlay"] as? ActionUIElement)
        XCTAssertEqual(overlay.type, "Circle")
    }

    func testBackgroundDictionaryConstruction() throws {
        let dict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "properties": ["text": "Tag"],
            "background": ["id": 2, "type": "RoundedRectangle", "properties": ["cornerRadius": 10, "fill": "blue"]] as [String: Any]
        ]
        let element = try ActionUIElement(from: dict, logger: logger)
        let bg = try XCTUnwrap(element.subviews?["background"] as? ActionUIElement)
        XCTAssertEqual(bg.type, "RoundedRectangle")
    }

    // MARK: - Encoding round-trip

    func testOverlayEncodingRoundTrip() throws {
        let original = ActionUIElement(
            id: 1, type: "Image",
            properties: ["systemName": "bell.fill"],
            subviews: ["overlay": ActionUIElement(id: 2, type: "Circle", properties: ["fill": "red"], subviews: nil)]
        )
        let data = try JSONEncoder(logger: logger).encode(original)
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertEqual(original, decoded)
        let overlay = try XCTUnwrap(decoded.subviews?["overlay"] as? ActionUIElement)
        XCTAssertEqual(overlay.id, 2)
        XCTAssertEqual(overlay.type, "Circle")
    }

    func testBackgroundEncodingRoundTrip() throws {
        let original = ActionUIElement(
            id: 1, type: "Text",
            properties: ["text": "Tag"],
            subviews: ["background": ActionUIElement(id: 2, type: "Capsule", properties: ["fill": "blue"], subviews: nil)]
        )
        let data = try JSONEncoder(logger: logger).encode(original)
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertEqual(original, decoded)
        let bg = try XCTUnwrap(decoded.subviews?["background"] as? ActionUIElement)
        XCTAssertEqual(bg.id, 2)
        XCTAssertEqual(bg.type, "Capsule")
    }

    // MARK: - findElement traversal

    func testFindElementTraversesOverlay() {
        let element = ActionUIElement(
            id: 1, type: "Image", properties: [:],
            subviews: ["overlay": ActionUIElement(id: 99, type: "Circle", properties: [:], subviews: nil)]
        )
        let found = element.findElement(by: 99)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.type, "Circle")
    }

    func testFindElementTraversesBackground() {
        let element = ActionUIElement(
            id: 1, type: "Text", properties: [:],
            subviews: ["background": ActionUIElement(id: 88, type: "Capsule", properties: [:], subviews: nil)]
        )
        let found = element.findElement(by: 88)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.type, "Capsule")
    }

    // MARK: - ViewModel registration via loadDescription

    func testOverlayViewModelRegistered() throws {
        let json = """
        {
            "id": 1,
            "type": "Text",
            "properties": { "text": "Hello", "overlayAlignment": "topTrailing" },
            "overlay": {
                "id": 2,
                "type": "Circle",
                "properties": { "fill": "red", "frame": { "width": 12, "height": 12 } }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
        XCTAssertNotNil(windowModel.viewModels[element.id], "Parent view should have a ViewModel")
        let overlay = try XCTUnwrap(element.subviews?["overlay"] as? ActionUIElement)
        XCTAssertNotNil(windowModel.viewModels[overlay.id], "Overlay child should have its own ViewModel")
    }

    func testBackgroundViewModelRegistered() throws {
        let json = """
        {
            "id": 1,
            "type": "Text",
            "properties": { "text": "Tag", "padding": 8 },
            "background": {
                "id": 2,
                "type": "Capsule",
                "properties": { "fill": "blue" }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
        XCTAssertNotNil(windowModel.viewModels[element.id])
        let bg = try XCTUnwrap(element.subviews?["background"] as? ActionUIElement)
        XCTAssertNotNil(windowModel.viewModels[bg.id], "backgroundView child should have its own ViewModel")
    }
}
