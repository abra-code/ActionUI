// Tests/Views/ToolbarItemTests.swift
/*
 ToolbarItemTests.swift

 Tests for the ToolbarItem component and the "toolbar" subview key in ActionUI.
 Verifies JSON decoding, property validation, ViewModel population, and element traversal.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToolbarItemTests: XCTestCase {
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

    // MARK: - ToolbarItem.validateProperties

    func testToolbarItemValidatePropertiesValidPlacement() {
        let validPlacements = [
            "automatic", "principal",
            "confirmationAction", "cancellationAction", "destructiveAction",
            "primaryAction", "secondaryAction",
            "topBarLeading", "topBarTrailing",
            "bottomBar", "keyboard",
            "navigation", "status"
        ]

        for placement in validPlacements {
            let properties: [String: Any] = ["placement": placement]
            let validated = ActionUI.ToolbarItem.validateProperties(properties, logger)
            XCTAssertEqual(validated["placement"] as? String, placement,
                           "Placement '\(placement)' should be preserved")
        }
    }

    func testToolbarItemValidatePropertiesInvalidPlacement() {
        let properties: [String: Any] = ["placement": "floating"]
        let validated = ActionUI.ToolbarItem.validateProperties(properties, logger)
        XCTAssertEqual(validated["placement"] as? String, "automatic",
                       "Invalid placement should default to 'automatic'")
    }

    func testToolbarItemValidatePropertiesWrongTypePlacement() {
        let properties: [String: Any] = ["placement": 42]
        let validated = ActionUI.ToolbarItem.validateProperties(properties, logger)
        XCTAssertEqual(validated["placement"] as? String, "automatic",
                       "Non-string placement should default to 'automatic'")
    }

    func testToolbarItemValidatePropertiesMissingPlacement() {
        let properties: [String: Any] = [:]
        let validated = ActionUI.ToolbarItem.validateProperties(properties, logger)
        XCTAssertNil(validated["placement"], "Missing placement should remain nil (defaults to automatic at render)")
    }

    // MARK: - toolbar subview key decoding

    func testParentElementWithToolbarSubview() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [:],
            "toolbar": [
                [
                    "id": 10,
                    "type": "ToolbarItem",
                    "properties": ["placement": "topBarTrailing"],
                    "content": ["id": 100, "type": "Button", "properties": ["title": "Done", "actionID": "done"]]
                ]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "VStack")

        guard let toolbarItems = element.subviews?["toolbar"] as? [any ActionUIElementBase] else {
            XCTFail("toolbar subview should be a [ActionUIElementBase]")
            return
        }

        XCTAssertEqual(toolbarItems.count, 1, "Should have one ToolbarItem")
        XCTAssertEqual(toolbarItems[0].id, 10)
        XCTAssertEqual(toolbarItems[0].type, "ToolbarItem")
        XCTAssertEqual(toolbarItems[0].properties["placement"] as? String, "topBarTrailing")

        guard let itemContent = toolbarItems[0].subviews?["content"] as? (any ActionUIElementBase) else {
            XCTFail("ToolbarItem should have a content element")
            return
        }
        XCTAssertEqual(itemContent.id, 100)
        XCTAssertEqual(itemContent.type, "Button")
    }

    func testMultipleToolbarItems() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "List",
          "properties": {},
          "toolbar": [
            {
              "id": 10,
              "type": "ToolbarItem",
              "properties": { "placement": "topBarLeading" },
              "content": { "id": 100, "type": "Button", "properties": { "title": "Edit", "actionID": "edit" } }
            },
            {
              "id": 11,
              "type": "ToolbarItem",
              "properties": { "placement": "topBarTrailing" },
              "content": { "id": 101, "type": "Button", "properties": { "title": "Add", "actionID": "add" } }
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let toolbarItems = element.subviews?["toolbar"] as? [any ActionUIElementBase] else {
            XCTFail("toolbar subview should exist"); return
        }

        XCTAssertEqual(toolbarItems.count, 2, "Should have two ToolbarItems")
        XCTAssertEqual(toolbarItems[0].id, 10)
        XCTAssertEqual(toolbarItems[0].properties["placement"] as? String, "topBarLeading")
        XCTAssertEqual(toolbarItems[1].id, 11)
        XCTAssertEqual(toolbarItems[1].properties["placement"] as? String, "topBarTrailing")
    }

    // MARK: - ViewModel population

    func testToolbarItemViewModelsPopulated() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "VStack",
          "properties": {},
          "toolbar": [
            {
              "id": 10,
              "type": "ToolbarItem",
              "properties": { "placement": "topBarTrailing" },
              "content": { "id": 100, "type": "Button", "properties": { "title": "Done" } }
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let _ = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            XCTFail("WindowModel should exist"); return
        }

        XCTAssertNotNil(windowModel.viewModels[1],   "Root element should have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[10],  "ToolbarItem should have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[100], "ToolbarItem's Button content should have a ViewModel")
    }

    func testToolbarItemValidatedPlacementInViewModel() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "VStack",
          "properties": {},
          "toolbar": [
            {
              "id": 10,
              "type": "ToolbarItem",
              "properties": { "placement": "confirmationAction" },
              "content": { "id": 100, "type": "Button", "properties": { "title": "Save" } }
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let _ = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let toolbarItemModel = windowModel.viewModels[10] else {
            XCTFail("ToolbarItem ViewModel should exist"); return
        }

        XCTAssertEqual(toolbarItemModel.validatedProperties["placement"] as? String, "confirmationAction",
                       "ToolbarItem ViewModel should hold the validated placement")
    }

    // MARK: - findElement traversal

    func testFindElementInToolbarItems() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [:],
            "toolbar": [
                [
                    "id": 10,
                    "type": "ToolbarItem",
                    "properties": ["placement": "principal"],
                    "content": ["id": 99, "type": "Text", "properties": ["text": "Title"]]
                ]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)

        let foundItem = element.findElement(by: 10)
        XCTAssertNotNil(foundItem, "Should find ToolbarItem by ID")
        XCTAssertEqual(foundItem?.type, "ToolbarItem")

        let foundContent = element.findElement(by: 99)
        XCTAssertNotNil(foundContent, "Should find ToolbarItem content by ID")
        XCTAssertEqual(foundContent?.type, "Text")
    }

    // MARK: - Encode / decode round-trip

    func testToolbarSubviewEncodingRoundTrip() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "NavigationStack",
          "content": {
            "id": 2,
            "type": "List",
            "properties": {},
            "toolbar": [
              {
                "id": 10,
                "type": "ToolbarItem",
                "properties": { "placement": "topBarTrailing" },
                "content": { "id": 100, "type": "Button", "properties": { "title": "Done" } }
              }
            ]
          }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let original = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let reencoded = try encoder.encode(original)

        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: reencoded)

        guard let contentElement = original.subviews?["content"] as? ActionUIElement,
              let toolbarItems = contentElement.subviews?["toolbar"] as? [any ActionUIElementBase] else {
            XCTFail("Original should have content with toolbar"); return
        }
        guard let decodedContent = decoded.subviews?["content"] as? ActionUIElement,
              let decodedToolbar = decodedContent.subviews?["toolbar"] as? [any ActionUIElementBase] else {
            XCTFail("Decoded should have content with toolbar"); return
        }

        XCTAssertEqual(toolbarItems.count, decodedToolbar.count, "Toolbar item count should round-trip")
        XCTAssertEqual(toolbarItems[0].id, decodedToolbar[0].id, "ToolbarItem ID should round-trip")
        XCTAssertEqual(toolbarItems[0].properties["placement"] as? String,
                       decodedToolbar[0].properties["placement"] as? String,
                       "Placement should round-trip")

        // Verify content child round-trips
        guard let originalContent = toolbarItems[0].subviews?["content"] as? (any ActionUIElementBase),
              let decodedItemContent = decodedToolbar[0].subviews?["content"] as? (any ActionUIElementBase) else {
            XCTFail("ToolbarItem content should round-trip"); return
        }
        XCTAssertEqual(originalContent.id, decodedItemContent.id, "ToolbarItem content ID should round-trip")
    }

    // MARK: - toolbarTitleDisplayMode validation

    func testToolbarTitleDisplayModeValidValues() throws {
        let validModes = ["automatic", "inline", "large", "inlineLarge"]
        for mode in validModes {
            let properties: [String: Any] = ["toolbarTitleDisplayMode": mode]
            let validated = View.validateProperties(properties, logger)
            XCTAssertEqual(validated["toolbarTitleDisplayMode"] as? String, mode,
                           "Mode '\(mode)' should be preserved")
        }
    }

    func testToolbarTitleDisplayModeInvalidValue() {
        let properties: [String: Any] = ["toolbarTitleDisplayMode": "giant"]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["toolbarTitleDisplayMode"],
                     "Invalid toolbarTitleDisplayMode should be nil")
    }

    func testToolbarTitleDisplayModeInvalidType() {
        let properties: [String: Any] = ["toolbarTitleDisplayMode": true]
        let validated = View.validateProperties(properties, logger)
        XCTAssertNil(validated["toolbarTitleDisplayMode"],
                     "Non-string toolbarTitleDisplayMode should be nil")
    }

    // MARK: - Principal item (custom navigation title)

    func testPrincipalToolbarItem() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "VStack",
          "properties": {},
          "toolbar": [
            {
              "id": 20,
              "type": "ToolbarItem",
              "properties": { "placement": "principal" },
              "content": {
                "id": 200,
                "type": "Text",
                "properties": { "text": "Custom Title" }
              }
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let toolbar = element.subviews?["toolbar"] as? [any ActionUIElementBase],
              let principalItem = toolbar.first else {
            XCTFail("toolbar should have one item"); return
        }

        XCTAssertEqual(principalItem.id, 20)
        XCTAssertEqual(principalItem.properties["placement"] as? String, "principal")

        guard let content = principalItem.subviews?["content"] as? (any ActionUIElementBase) else {
            XCTFail("Principal item should have a content element"); return
        }
        XCTAssertEqual(content.type, "Text")
        XCTAssertEqual(content.properties["text"] as? String, "Custom Title")

        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        XCTAssertNotNil(windowModel?.viewModels[20],  "ToolbarItem should have a ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[200], "Text content should have a ViewModel")
    }

    // MARK: - Composite content (HStack as the single content view)

    func testToolbarItemWithCompositeContent() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "VStack",
          "properties": {},
          "toolbar": [
            {
              "id": 30,
              "type": "ToolbarItem",
              "properties": { "placement": "principal" },
              "content": {
                "id": 300,
                "type": "HStack",
                "properties": { "spacing": 6.0 },
                "children": [
                  { "id": 301, "type": "Image", "properties": { "systemName": "envelope.fill" } },
                  { "id": 302, "type": "Text",  "properties": { "text": "Inbox" } }
                ]
              }
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let toolbar = element.subviews?["toolbar"] as? [any ActionUIElementBase],
              let item = toolbar.first,
              let content = item.subviews?["content"] as? (any ActionUIElementBase) else {
            XCTFail("ToolbarItem should have a single content element"); return
        }

        XCTAssertEqual(content.type, "HStack")
        XCTAssertEqual(content.id, 300)

        guard let hstackChildren = content.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("HStack content should have children"); return
        }
        XCTAssertEqual(hstackChildren.count, 2)
        XCTAssertEqual(hstackChildren[0].type, "Image")
        XCTAssertEqual(hstackChildren[1].type, "Text")

        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        XCTAssertNotNil(windowModel?.viewModels[300], "HStack content should have a ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[301], "Image should have a ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[302], "Text should have a ViewModel")
    }
}
