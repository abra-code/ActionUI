// Tests/Views/PopoverTests.swift
/*
 PopoverTests.swift

 Tests for the popover modifier support in the ActionUI component library.
 Verifies JSON decoding of the "popover" subview key, popoverArrowEdge property validation,
 and popover state initialization.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class PopoverTests: XCTestCase {
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

    // MARK: - popoverArrowEdge validation

    func testPopoverArrowEdgeValid() {
        for edge in ["top", "bottom", "leading", "trailing"] {
            let validated = View.validateProperties(["popoverArrowEdge": edge], logger)
            XCTAssertEqual(validated["popoverArrowEdge"] as? String, edge, "'\(edge)' should be a valid popoverArrowEdge")
        }
    }

    func testPopoverArrowEdgeInvalidValue() {
        let validated = View.validateProperties(["popoverArrowEdge": "left"], logger)
        XCTAssertEqual(validated["popoverArrowEdge"] as? String, "top", "Invalid popoverArrowEdge should default to 'top'")
    }

    func testPopoverArrowEdgeInvalidType() {
        let validated = View.validateProperties(["popoverArrowEdge": 123], logger)
        XCTAssertNil(validated["popoverArrowEdge"], "Non-String popoverArrowEdge should be removed")
    }

    func testPopoverArrowEdgeMissing() {
        let validated = View.validateProperties([:], logger)
        XCTAssertNil(validated["popoverArrowEdge"], "Missing popoverArrowEdge should be nil")
    }

    // MARK: - JSON decoding with popover subview

    func testPopoverSubviewDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Button",
            "properties": {
                "title": "Show Info",
                "popoverArrowEdge": "bottom"
            },
            "popover": {
                "id": 2,
                "type": "Text",
                "properties": { "text": "Popover content" }
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)

        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Button", "Element type should be Button")
        XCTAssertEqual(element.properties["popoverArrowEdge"] as? String, "bottom", "popoverArrowEdge should be bottom")

        if let popover = element.subviews?["popover"] as? ActionUIElement {
            XCTAssertEqual(popover.id, 2, "Popover child ID should be 2")
            XCTAssertEqual(popover.type, "Text", "Popover child type should be Text")
            XCTAssertEqual(popover.properties["text"] as? String, "Popover content", "Popover text should match")
        } else {
            XCTFail("Popover subview should be a valid ActionUIElement")
        }
    }

    func testPopoverSubviewAbsent() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Button",
            "properties": { "title": "No Popover" }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        XCTAssertNil(element.subviews?["popover"], "Popover subview should be nil when not specified")
    }

    // MARK: - Encoding round-trip

    func testPopoverEncodingRoundTrip() throws {
        let original = ActionUIElement(
            id: 1,
            type: "Button",
            properties: ["title": "Show"],
            subviews: [
                "popover": ActionUIElement(id: 2, type: "Text", properties: ["text": "Hello"], subviews: nil)
            ]
        )

        let data = try JSONEncoder(logger: logger).encode(original)
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        XCTAssertEqual(original, decoded, "Encoded and decoded elements should be equal")
        if let popover = decoded.subviews?["popover"] as? ActionUIElement {
            XCTAssertEqual(popover.id, 2, "Round-tripped popover ID should match")
            XCTAssertEqual(popover.type, "Text", "Round-tripped popover type should match")
        } else {
            XCTFail("Popover should survive encoding round-trip")
        }
    }

    // MARK: - Dictionary construction

    func testPopoverDictionaryConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Button",
            "properties": [
                "title": "Show Info",
                "popoverArrowEdge": "trailing"
            ],
            "popover": [
                "id": 2,
                "type": "Text",
                "properties": ["text": "Info"]
            ] as [String: Any]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)

        XCTAssertEqual(element.type, "Button", "Type should be Button")
        if let popover = element.subviews?["popover"] as? ActionUIElement {
            XCTAssertEqual(popover.id, 2, "Popover child ID should be 2")
            XCTAssertEqual(popover.type, "Text", "Popover child type should be Text")
        } else {
            XCTFail("Popover subview should be parsed from dictionary")
        }
    }

    // MARK: - findElement traversal

    func testFindElementTraversesPopover() throws {
        let element = ActionUIElement(
            id: 1,
            type: "Button",
            properties: ["title": "Show"],
            subviews: [
                "popover": ActionUIElement(id: 42, type: "Text", properties: ["text": "Found me"], subviews: nil)
            ]
        )

        let found = element.findElement(by: 42)
        XCTAssertNotNil(found, "findElement should find elements inside popover subview")
        XCTAssertEqual(found?.id, 42, "Found element ID should be 42")
        XCTAssertEqual(found?.type, "Text", "Found element type should be Text")
    }

    func testFindElementReturnsNilForMissingPopoverChild() {
        let element = ActionUIElement(
            id: 1,
            type: "Button",
            properties: [:],
            subviews: [
                "popover": ActionUIElement(id: 2, type: "Text", properties: [:], subviews: nil)
            ]
        )

        XCTAssertNil(element.findElement(by: 999), "findElement should return nil for non-existent ID")
    }

    // MARK: - Equatable

    func testEquatableWithIdenticalPopover() {
        let element1 = ActionUIElement(
            id: 1, type: "Button", properties: ["title": "Show"],
            subviews: ["popover": ActionUIElement(id: 2, type: "Text", properties: ["text": "Hello"], subviews: nil)]
        )
        let element2 = ActionUIElement(
            id: 1, type: "Button", properties: ["title": "Show"],
            subviews: ["popover": ActionUIElement(id: 2, type: "Text", properties: ["text": "Hello"], subviews: nil)]
        )
        XCTAssertEqual(element1, element2, "Elements with identical popover should be equal")
    }

    func testEquatableWithDifferentPopover() {
        let element1 = ActionUIElement(
            id: 1, type: "Button", properties: ["title": "Show"],
            subviews: ["popover": ActionUIElement(id: 2, type: "Text", properties: ["text": "Hello"], subviews: nil)]
        )
        let element2 = ActionUIElement(
            id: 1, type: "Button", properties: ["title": "Show"],
            subviews: ["popover": ActionUIElement(id: 2, type: "Text", properties: ["text": "Different"], subviews: nil)]
        )
        XCTAssertNotEqual(element1, element2, "Elements with different popover content should not be equal")
    }

    // MARK: - ViewModel popover state via loadDescription

    func testPopoverViewModelCreatedViaLoadDescription() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Button",
            "properties": { "title": "Show" },
            "popover": {
                "id": 2,
                "type": "Text",
                "properties": { "text": "Popover" }
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("WindowModel should exist")
            return
        }

        XCTAssertNotNil(windowModel.viewModels[element.id], "Parent Button should have a ViewModel")

        let popover = element.subviews?["popover"] as? ActionUIElement
        XCTAssertNotNil(popover, "Popover subview should exist")
        XCTAssertNotNil(windowModel.viewModels[popover!.id], "Popover child should have its own ViewModel")
    }
}
