// Tests/Views/SheetTests.swift
/*
 SheetTests.swift

 Tests for the sheet and fullScreenCover modifier support in ActionUI.
 Verifies JSON decoding of the "sheet" and "fullScreenCover" subview keys,
 property validation, state initialization, and ViewModel creation.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SheetTests: XCTestCase {
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

    // MARK: - sheetOnDismissActionID validation

    func testSheetOnDismissActionIDValid() {
        let validated = View.validateProperties(["sheetOnDismissActionID": "sheet.dismissed"], logger)
        XCTAssertEqual(validated["sheetOnDismissActionID"] as? String, "sheet.dismissed")
    }

    func testSheetOnDismissActionIDInvalidType() {
        let validated = View.validateProperties(["sheetOnDismissActionID": 123], logger)
        XCTAssertNil(validated["sheetOnDismissActionID"], "Non-String sheetOnDismissActionID should be removed")
    }

    func testSheetOnDismissActionIDMissing() {
        let validated = View.validateProperties([:], logger)
        XCTAssertNil(validated["sheetOnDismissActionID"], "Missing sheetOnDismissActionID should be nil")
    }

    // MARK: - fullScreenCoverOnDismissActionID validation

    func testFullScreenCoverOnDismissActionIDValid() {
        let validated = View.validateProperties(["fullScreenCoverOnDismissActionID": "cover.dismissed"], logger)
        XCTAssertEqual(validated["fullScreenCoverOnDismissActionID"] as? String, "cover.dismissed")
    }

    func testFullScreenCoverOnDismissActionIDInvalidType() {
        let validated = View.validateProperties(["fullScreenCoverOnDismissActionID": true], logger)
        XCTAssertNil(validated["fullScreenCoverOnDismissActionID"], "Non-String fullScreenCoverOnDismissActionID should be removed")
    }

    // MARK: - JSON decoding — sheet subview

    func testSheetSubviewDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Button",
            "properties": {
                "title": "Open Sheet",
                "sheetOnDismissActionID": "sheet.closed"
            },
            "sheet": {
                "id": 2,
                "type": "Text",
                "properties": { "text": "Sheet content" }
            }
        }
        """
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonString.data(using: .utf8)!)

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.properties["sheetOnDismissActionID"] as? String, "sheet.closed")

        let sheet = element.subviews?["sheet"] as? ActionUIElement
        XCTAssertNotNil(sheet, "sheet subview should be decoded")
        XCTAssertEqual(sheet?.id, 2)
        XCTAssertEqual(sheet?.type, "Text")
        XCTAssertEqual(sheet?.properties["text"] as? String, "Sheet content")
    }

    func testSheetSubviewAbsent() throws {
        let jsonString = """
        { "id": 1, "type": "Button", "properties": { "title": "No Sheet" } }
        """
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonString.data(using: .utf8)!)
        XCTAssertNil(element.subviews?["sheet"], "sheet subview should be nil when absent")
    }

    // MARK: - JSON decoding — fullScreenCover subview

    func testFullScreenCoverSubviewDecoding() throws {
        let jsonString = """
        {
            "id": 10,
            "type": "Button",
            "properties": { "title": "Go Full Screen" },
            "fullScreenCover": {
                "id": 11,
                "type": "VStack",
                "children": [
                    { "id": 12, "type": "Text", "properties": { "text": "Full screen!" } }
                ]
            }
        }
        """
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonString.data(using: .utf8)!)

        let cover = element.subviews?["fullScreenCover"] as? ActionUIElement
        XCTAssertNotNil(cover, "fullScreenCover subview should be decoded")
        XCTAssertEqual(cover?.id, 11)
        XCTAssertEqual(cover?.type, "VStack")
    }

    // MARK: - Dictionary construction

    func testSheetDictionaryConstruction() throws {
        let dict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": ["sheetOnDismissActionID": "closed"],
            "sheet": ["id": 2, "type": "Text", "properties": ["text": "Hello"]] as [String: Any]
        ]
        let element = try ActionUIElement(from: dict, logger: logger)
        let sheet = element.subviews?["sheet"] as? ActionUIElement
        XCTAssertNotNil(sheet)
        XCTAssertEqual(sheet?.id, 2)
    }

    // MARK: - Encoding round-trip

    func testSheetEncodingRoundTrip() throws {
        let original = ActionUIElement(
            id: 1,
            type: "Button",
            properties: ["title": "Open"],
            subviews: [
                "sheet": ActionUIElement(id: 2, type: "Text", properties: ["text": "Sheet"], subviews: nil)
            ]
        )

        let data = try JSONEncoder(logger: logger).encode(original)
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        XCTAssertEqual(original, decoded, "Sheet subview should survive encoding round-trip")
        let sheet = decoded.subviews?["sheet"] as? ActionUIElement
        XCTAssertEqual(sheet?.id, 2)
        XCTAssertEqual(sheet?.type, "Text")
    }

    func testFullScreenCoverEncodingRoundTrip() throws {
        let original = ActionUIElement(
            id: 1,
            type: "Button",
            properties: ["title": "Cover"],
            subviews: [
                "fullScreenCover": ActionUIElement(id: 5, type: "VStack", properties: [:], subviews: nil)
            ]
        )

        let data = try JSONEncoder(logger: logger).encode(original)
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertNotNil(decoded.subviews?["fullScreenCover"] as? ActionUIElement)
    }

    // MARK: - findElement traversal

    func testFindElementTraversesSheet() throws {
        let element = ActionUIElement(
            id: 1,
            type: "Button",
            properties: [:],
            subviews: [
                "sheet": ActionUIElement(id: 42, type: "Text", properties: ["text": "In sheet"], subviews: nil)
            ]
        )
        let found = element.findElement(by: 42)
        XCTAssertNotNil(found, "findElement should traverse into sheet subview")
        XCTAssertEqual(found?.id, 42)
    }

    func testFindElementTraversesFullScreenCover() {
        let element = ActionUIElement(
            id: 1,
            type: "Button",
            properties: [:],
            subviews: [
                "fullScreenCover": ActionUIElement(id: 99, type: "Text", properties: [:], subviews: nil)
            ]
        )
        XCTAssertNotNil(element.findElement(by: 99))
    }

    // MARK: - Equatable

    func testEquatableWithIdenticalSheet() {
        let e1 = ActionUIElement(id: 1, type: "Button", properties: [:],
            subviews: ["sheet": ActionUIElement(id: 2, type: "Text", properties: ["text": "A"], subviews: nil)])
        let e2 = ActionUIElement(id: 1, type: "Button", properties: [:],
            subviews: ["sheet": ActionUIElement(id: 2, type: "Text", properties: ["text": "A"], subviews: nil)])
        XCTAssertEqual(e1, e2)
    }

    func testEquatableWithDifferentSheetContent() {
        let e1 = ActionUIElement(id: 1, type: "Button", properties: [:],
            subviews: ["sheet": ActionUIElement(id: 2, type: "Text", properties: ["text": "A"], subviews: nil)])
        let e2 = ActionUIElement(id: 1, type: "Button", properties: [:],
            subviews: ["sheet": ActionUIElement(id: 2, type: "Text", properties: ["text": "B"], subviews: nil)])
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - ViewModel creation via loadDescription

    func testSheetViewModelCreatedViaLoadDescription() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Button",
            "properties": { "title": "Open" },
            "sheet": {
                "id": 2,
                "type": "Text",
                "properties": { "text": "Sheet" }
            }
        }
        """
        let element = try ActionUIModel.shared.loadDescription(from: jsonString.data(using: .utf8)!, format: "json", windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            XCTFail("WindowModel should exist"); return
        }

        XCTAssertNotNil(windowModel.viewModels[element.id], "Parent Button should have a ViewModel")
        let sheet = element.subviews?["sheet"] as? ActionUIElement
        XCTAssertNotNil(sheet)
        XCTAssertNotNil(windowModel.viewModels[sheet!.id], "Sheet child should have its own ViewModel")
    }

    func testFullScreenCoverViewModelCreatedViaLoadDescription() throws {
        let jsonString = """
        {
            "id": 10,
            "type": "VStack",
            "fullScreenCover": {
                "id": 11,
                "type": "Text",
                "properties": { "text": "Cover" }
            }
        }
        """
        let element = try ActionUIModel.shared.loadDescription(from: jsonString.data(using: .utf8)!, format: "json", windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            XCTFail("WindowModel should exist"); return
        }
        let cover = element.subviews?["fullScreenCover"] as? ActionUIElement
        XCTAssertNotNil(cover)
        XCTAssertNotNil(windowModel.viewModels[cover!.id], "fullScreenCover child should have its own ViewModel")
    }

    // MARK: - getElementInfo includes sheet/fullScreenCover children

    func testGetElementInfoIncludesSheetChild() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Button",
            "properties": { "title": "Open" },
            "sheet": { "id": 2, "type": "Text", "properties": { "text": "Sheet" } }
        }
        """
        _ = try ActionUIModel.shared.loadDescription(from: jsonString.data(using: .utf8)!, format: "json", windowUUID: windowUUID)
        let info = ActionUIModel.shared.getElementInfo(windowUUID: windowUUID)
        XCTAssertNotNil(info[2], "Sheet child with id=2 should appear in getElementInfo")
        XCTAssertEqual(info[2], "Text")
    }
}
