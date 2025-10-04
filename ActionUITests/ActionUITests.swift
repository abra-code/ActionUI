// Tests/ActionUITests.swift
/*
 ActionUITests.swift

 Integration tests for the ActionUI component library.
 Verifies the construction of an ActionUIView with a TextField element from a JSON description,
 ensuring proper state binding with ActionUIModel.shared.state and property validation.
 Uses Dictionary+Numeric extension to ensure numeric properties like padding are retrieved as Double and CGFloat.
 Verifies the construction of a WindowGroup with valid CommandMenu and CommandGroup elements from a JSON description,
 ensuring proper command parsing, validation, and scene construction.
*/

import XCTest
import SwiftUI
import CoreGraphics
@testable import ActionUI

@MainActor
final class ActionUITests: XCTestCase {
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
    
    func testActionUIViewWithTextFieldFromJSON() throws {
        // Arrange: Create JSON description for TextField with explicit floating-point padding
        let jsonString = """
        {
            "id": 1,
            "type": "TextField",
            "properties": {
                "placeholder": "Enter username",
                "textContentType": "username",
                "actionID": "text.submit",
                "padding": 8.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
                
        // Verify parsed element
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "TextField", "Element type should be TextField")
        XCTAssertEqual(element.properties["placeholder"] as? String, "Enter username", "Placeholder should match")
        XCTAssertEqual(element.properties["textContentType"] as? String, "username", "textContentType should match")
        XCTAssertEqual(element.properties["actionID"] as? String, "text.submit", "actionID should match")
        XCTAssertEqual(element.properties.double(forKey: "padding"), 8.0, "Padding should be retrieved as Double with value 8.0")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 8.0, "Padding should be retrieved as CGFloat with value 8.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")

        guard let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel from windowModel for element id: \(element.id)")
            return
        }
        
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let view = actionUIView.body // Access the body to trigger view construction
        
        // Assert: Verify model initialization
        XCTAssertEqual(viewModel.value as? String, "", "TextField state should initialize value to empty string")
        
        // Assert: Verify validated properties
        let validatedProperties = viewModel.validatedProperties
        
        XCTAssertFalse(validatedProperties.isEmpty, "Validated properties should exist")
        XCTAssertEqual(validatedProperties["placeholder"] as? String, "Enter username", "Validated placeholder should match")
        XCTAssertEqual(validatedProperties["textContentType"] as? String, "username", "Validated textContentType should match")
        XCTAssertEqual(validatedProperties["actionID"] as? String, "text.submit", "Validated actionID should match")
        XCTAssertEqual(validatedProperties.double(forKey: "padding"), 8.0, "Validated padding should be Double with value 8.0")
        XCTAssertEqual(validatedProperties.cgFloat(forKey: "padding"), 8.0, "Validated padding should be CGFloat with value 8.0")
        
        // Assert: Verify view construction
        XCTAssertFalse(view is SwiftUI.EmptyView, "ActionUIView body should not return EmptyView")
        XCTAssertTrue(view is AnyView, "ActionUIView body should return AnyView after applying modifiers")
        
        // Assert: Verify model binding
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: "testuser")
        let updatedValue = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(updatedValue as? String, "testuser", "TextField state should update value correctly")
        
        // Log state for debugging
        logger.log("Final viewModel.states for viewID \(element.id): \(String(describing: viewModel.states))", .debug)
    }
    
    func testWindowGroupWithCommandsFromJSON() throws {
        // Arrange: Create JSON description for WindowGroup with valid CommandMenu and CommandGroup
        let jsonString = """
        {
            "id": 1,
            "type": "WindowGroup",
            "properties": {
                "title": "Test Window"
            },
            "content": {
                "id": 2,
                "type": "Text",
                "properties": {
                    "text": "Welcome"
                }
            },
            "commands": [
                {
                    "id": 3,
                    "type": "CommandMenu",
                    "properties": {
                        "name": "File"
                    },
                    "children": [
                        {
                            "id": 4,
                            "type": "Button",
                            "properties": {
                                "title": "New",
                                "actionID": "file.new",
                                "keyboardShortcut": {
                                    "key": "n",
                                    "modifiers": ["command"]
                                }
                            }
                        },
                        {
                            "id": 5,
                            "type": "Divider",
                            "properties": {}
                        },
                        {
                            "id": 6,
                            "type": "Button",
                            "properties": {
                                "title": "Save",
                                "actionID": "file.save",
                                "keyboardShortcut": {
                                    "key": "s",
                                    "modifiers": ["command"]
                                }
                            }
                        }
                    ]
                },
                {
                    "id": 7,
                    "type": "CommandGroup",
                    "properties": {
                        "placement": "replacing",
                        "placementTarget": "newItem"
                    },
                    "children": [
                        {
                            "id": 8,
                            "type": "Button",
                            "properties": {
                                "title": "Custom New",
                                "actionID": "custom.new",
                                "keyboardShortcut": {
                                    "key": "n",
                                    "modifiers": ["command", "shift"]
                                }
                            }
                        }
                    ]
                }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Act: Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
        
        // Assert: Verify parsed WindowGroup element
        XCTAssertEqual(element.id, 1, "WindowGroup element ID should be 1")
        XCTAssertEqual(element.type, "WindowGroup", "Element type should be WindowGroup")
        XCTAssertEqual(element.properties["title"] as? String, "Test Window", "Title should match")
        
        // Verify content element
        guard let contentElement = element.subviews?["content"] as? any ActionUIElementBase else {
            XCTFail("Failed to retrieve content element from WindowGroup")
            return
        }
        XCTAssertEqual(contentElement.id, 2, "Content element ID should be 2")
        XCTAssertEqual(contentElement.type, "Text", "Content element type should be Text")
        XCTAssertEqual(contentElement.properties["text"] as? String, "Welcome", "Content text should match")
        XCTAssertNil(contentElement.subviews?["children"], "Content children should be nil")
        
        // Verify commands
        guard let commands = element.subviews?["commands"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve commands from WindowGroup")
            return
        }
        XCTAssertEqual(commands.count, 2, "WindowGroup should have 2 command elements")
        
        // Verify CommandMenu
        let commandMenu = commands[0]
        XCTAssertEqual(commandMenu.id, 3, "CommandMenu ID should be 3")
        XCTAssertEqual(commandMenu.type, "CommandMenu", "Command type should be CommandMenu")
        XCTAssertEqual(commandMenu.properties["name"] as? String, "File", "CommandMenu name should match")
        guard let menuChildren = commandMenu.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve CommandMenu children")
            return
        }
        XCTAssertEqual(menuChildren.count, 3, "CommandMenu should have 3 children")
        
        // Verify CommandMenu children
        let button1 = menuChildren[0]
        XCTAssertEqual(button1.id, 4, "Button1 ID should be 4")
        XCTAssertEqual(button1.type, "Button", "Button1 type should be Button")
        XCTAssertEqual(button1.properties["title"] as? String, "New", "Button1 title should match")
        XCTAssertEqual(button1.properties["actionID"] as? String, "file.new", "Button1 actionID should match")
        XCTAssertEqual((button1.properties["keyboardShortcut"] as? [String: Any])?["key"] as? String, "n", "Button1 keyboardShortcut key should match")
        XCTAssertEqual((button1.properties["keyboardShortcut"] as? [String: Any])?["modifiers"] as? [String], ["command"], "Button1 keyboardShortcut modifiers should match")
        
        let divider = menuChildren[1]
        XCTAssertEqual(divider.id, 5, "Divider ID should be 5")
        XCTAssertEqual(divider.type, "Divider", "Divider type should be Divider")
        XCTAssertTrue(divider.properties.isEmpty, "Divider properties should be empty")
        
        let button2 = menuChildren[2]
        XCTAssertEqual(button2.id, 6, "Button2 ID should be 6")
        XCTAssertEqual(button2.type, "Button", "Button2 type should be Button")
        XCTAssertEqual(button2.properties["title"] as? String, "Save", "Button2 title should match")
        XCTAssertEqual(button2.properties["actionID"] as? String, "file.save", "Button2 actionID should match")
        XCTAssertEqual((button2.properties["keyboardShortcut"] as? [String: Any])?["key"] as? String, "s", "Button2 keyboardShortcut key should match")
        XCTAssertEqual((button2.properties["keyboardShortcut"] as? [String: Any])?["modifiers"] as? [String], ["command"], "Button2 keyboardShortcut modifiers should match")
        
        // Verify CommandGroup
        let commandGroup = commands[1]
        XCTAssertEqual(commandGroup.id, 7, "CommandGroup ID should be 7")
        XCTAssertEqual(commandGroup.type, "CommandGroup", "Command type should be CommandGroup")
        XCTAssertEqual(commandGroup.properties["placement"] as? String, "replacing", "CommandGroup placement should match")
        XCTAssertEqual(commandGroup.properties["placementTarget"] as? String, "newItem", "CommandGroup placementTarget should match")
        guard let groupChildren = commandGroup.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve CommandGroup children")
            return
        }
        XCTAssertEqual(groupChildren.count, 1, "CommandGroup should have 1 child")
        
        let groupButton = groupChildren[0]
        XCTAssertEqual(groupButton.id, 8, "Group Button ID should be 8")
        XCTAssertEqual(groupButton.type, "Button", "Group Button type should be Button")
        XCTAssertEqual(groupButton.properties["title"] as? String, "Custom New", "Group Button title should match")
        XCTAssertEqual(groupButton.properties["actionID"] as? String, "custom.new", "Group Button actionID should match")
        XCTAssertEqual((groupButton.properties["keyboardShortcut"] as? [String: Any])?["key"] as? String, "n", "Group Button keyboardShortcut key should match")
        XCTAssertEqual((groupButton.properties["keyboardShortcut"] as? [String: Any])?["modifiers"] as? [String], ["command", "shift"], "Group Button keyboardShortcut modifiers should match")
        
        // Act: Instantiate WindowGroup
        let windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
        _ = WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)

        // Assert: Verify content view model
        guard let contentViewModel = windowModel.viewModels[contentElement.id] else {
            XCTFail("Failed to retrieve viewModel for content element id: \(contentElement.id)")
            return
        }
        XCTAssertTrue(contentViewModel.validatedProperties["text"] as? String == "Welcome", "Content view model validated properties should match")
        
        // Verify command view models
        let validCommandIds = [3, 7] // CommandMenu and CommandGroup
        for commandId in validCommandIds {
            guard let commandViewModel = windowModel.viewModels[commandId] else {
                XCTFail("Failed to retrieve viewModel for command id: \(commandId)")
                return
            }
            XCTAssertFalse(commandViewModel.validatedProperties.isEmpty, "Command view model validated properties should not be empty")
        }
        
        // Verify child view models for CommandMenu
        let menuChildIds = [4, 5, 6]
        for childId in menuChildIds {
            guard let childViewModel = windowModel.viewModels[childId] else {
                XCTFail("Failed to retrieve viewModel for CommandMenu child id: \(childId)")
                return
            }
            if childId != 5 { // Divider has empty properties
                XCTAssertFalse(childViewModel.validatedProperties.isEmpty, "CommandMenu child view model validated properties should not be empty")
            }
        }
        
        // Verify child view model for CommandGroup
        let groupChildId = 8
        guard let groupChildViewModel = windowModel.viewModels[groupChildId] else {
            XCTFail("Failed to retrieve viewModel for CommandGroup child id: \(groupChildId)")
            return
        }
        XCTAssertFalse(groupChildViewModel.validatedProperties.isEmpty, "CommandGroup child view model validated properties should not be empty")
        
        // Log state for debugging
        logger.log("Final windowModel for windowUUID \(windowUUID!): \(String(describing: windowModel))", .debug)
    }
}
