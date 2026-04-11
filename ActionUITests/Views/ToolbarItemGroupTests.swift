// Tests/Views/ToolbarItemGroupTests.swift
/*
 ToolbarItemGroupTests.swift

 Tests for the ToolbarItemGroup component in ActionUI.
 Verifies placement validation, JSON decoding, ViewModel population,
 and that ToolbarItem and ToolbarItemGroup can coexist in the same toolbar array.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToolbarItemGroupTests: XCTestCase {
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

    // MARK: - validateProperties

    func testValidPlacement() {
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
            let validated = ActionUI.ToolbarItemGroup.validateProperties(properties, logger)
            XCTAssertEqual(validated["placement"] as? String, placement,
                           "Placement '\(placement)' should be preserved")
        }
    }

    func testInvalidPlacementDefaultsToAutomatic() {
        let properties: [String: Any] = ["placement": "sidebar"]
        let validated = ActionUI.ToolbarItemGroup.validateProperties(properties, logger)
        XCTAssertEqual(validated["placement"] as? String, "automatic",
                       "Invalid placement should default to 'automatic'")
    }

    func testWrongTypePlacementDefaultsToAutomatic() {
        let properties: [String: Any] = ["placement": 99]
        let validated = ActionUI.ToolbarItemGroup.validateProperties(properties, logger)
        XCTAssertEqual(validated["placement"] as? String, "automatic",
                       "Non-string placement should default to 'automatic'")
    }

    func testMissingPlacementRemainsNil() {
        let properties: [String: Any] = [:]
        let validated = ActionUI.ToolbarItemGroup.validateProperties(properties, logger)
        XCTAssertNil(validated["placement"],
                     "Missing placement should remain nil (defaults to automatic at render)")
    }

    // MARK: - JSON decoding

    func testToolbarItemGroupDecoding() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "List",
          "properties": {},
          "toolbar": [
            {
              "id": 10,
              "type": "ToolbarItemGroup",
              "properties": { "placement": "topBarTrailing" },
              "children": [
                { "id": 100, "type": "Button", "properties": { "title": "Edit",  "actionID": "edit"  } },
                { "id": 101, "type": "Button", "properties": { "title": "Share", "actionID": "share" } }
              ]
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

        XCTAssertEqual(toolbarItems.count, 1)
        XCTAssertEqual(toolbarItems[0].type, "ToolbarItemGroup")
        XCTAssertEqual(toolbarItems[0].id, 10)
        XCTAssertEqual(toolbarItems[0].properties["placement"] as? String, "topBarTrailing")

        guard let children = toolbarItems[0].subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("ToolbarItemGroup should have children"); return
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].id, 100)
        XCTAssertEqual(children[1].id, 101)
    }

    // MARK: - ViewModel population

    func testViewModelsPopulated() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "VStack",
          "properties": {},
          "toolbar": [
            {
              "id": 20,
              "type": "ToolbarItemGroup",
              "properties": { "placement": "topBarTrailing" },
              "children": [
                { "id": 200, "type": "Button", "properties": { "title": "A" } },
                { "id": 201, "type": "Button", "properties": { "title": "B" } }
              ]
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

        XCTAssertNotNil(windowModel.viewModels[1],   "Root should have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[20],  "ToolbarItemGroup should have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[200], "First child should have a ViewModel")
        XCTAssertNotNil(windowModel.viewModels[201], "Second child should have a ViewModel")
    }

    func testValidatedPlacementInViewModel() throws {
        let jsonString = """
        {
          "id": 1,
          "type": "VStack",
          "properties": {},
          "toolbar": [
            {
              "id": 30,
              "type": "ToolbarItemGroup",
              "properties": { "placement": "primaryAction" },
              "children": [
                { "id": 300, "type": "Button", "properties": { "title": "New" } }
              ]
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let _ = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let groupModel = windowModel.viewModels[30] else {
            XCTFail("ToolbarItemGroup ViewModel should exist"); return
        }

        XCTAssertEqual(groupModel.validatedProperties["placement"] as? String, "primaryAction")
    }

    // MARK: - Mixed ToolbarItem and ToolbarItemGroup in same toolbar

    func testMixedToolbarItemAndGroup() throws {
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
              "children": [
                { "id": 100, "type": "Button", "properties": { "title": "Back" } }
              ]
            },
            {
              "id": 11,
              "type": "ToolbarItemGroup",
              "properties": { "placement": "topBarTrailing" },
              "children": [
                { "id": 110, "type": "Button", "properties": { "title": "Edit"  } },
                { "id": 111, "type": "Button", "properties": { "title": "Share" } }
              ]
            }
          ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data"); return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let toolbar = element.subviews?["toolbar"] as? [any ActionUIElementBase] else {
            XCTFail("toolbar should exist"); return
        }

        XCTAssertEqual(toolbar.count, 2)
        XCTAssertEqual(toolbar[0].type, "ToolbarItem")
        XCTAssertEqual(toolbar[1].type, "ToolbarItemGroup")

        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        XCTAssertNotNil(windowModel?.viewModels[10],  "ToolbarItem should have ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[11],  "ToolbarItemGroup should have ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[100], "ToolbarItem child should have ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[110], "ToolbarItemGroup first child should have ViewModel")
        XCTAssertNotNil(windowModel?.viewModels[111], "ToolbarItemGroup second child should have ViewModel")
    }

    // MARK: - findElement traversal

    func testFindElementInToolbarItemGroup() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [:],
            "toolbar": [
                [
                    "id": 50,
                    "type": "ToolbarItemGroup",
                    "properties": ["placement": "topBarTrailing"],
                    "children": [
                        ["id": 500, "type": "Button", "properties": ["title": "X"]],
                        ["id": 501, "type": "Button", "properties": ["title": "Y"]]
                    ]
                ]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)

        let foundGroup = element.findElement(by: 50)
        XCTAssertNotNil(foundGroup, "Should find ToolbarItemGroup by ID")
        XCTAssertEqual(foundGroup?.type, "ToolbarItemGroup")

        let foundChild = element.findElement(by: 501)
        XCTAssertNotNil(foundChild, "Should find child inside ToolbarItemGroup")
        XCTAssertEqual(foundChild?.type, "Button")
    }
}
