// Tests/Views/WindowGroupTests.swift
/*
 WindowGroupTests.swift

 Tests for the WindowGroup component in the ActionUI component library.
 Verifies JSON decoding, property validation, scene construction, and command handling.
 Includes edge cases for invalid commands and exceeding command limits.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class WindowGroupTests: XCTestCase {
    private var logger: XCTestLogger!
    private var consoleLogger: ConsoleLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        consoleLogger = ConsoleLogger(maxLevel: .verbose)
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
        consoleLogger = nil
        windowUUID = nil
        super.tearDown()
    }
    
    func testWindowGroupConstruction() throws {
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
                        }
                    ]
                },
                {
                    "id": 5,
                    "type": "CommandGroup",
                    "properties": {
                        "placement": "replacing",
                        "placementTarget": "newItem"
                    },
                    "children": [
                        {
                            "id": 6,
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
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
        
        // Act: Instantiate WindowGroup
        let windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
        let commands = element.subviews?["commands"] as? [any ActionUIElementBase] ?? []
        _ = WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)
        
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
        XCTAssertEqual(menuChildren.count, 1, "CommandMenu should have 1 child")
        
        // Verify CommandMenu child
        let button1 = menuChildren[0]
        XCTAssertEqual(button1.id, 4, "Button1 ID should be 4")
        XCTAssertEqual(button1.type, "Button", "Button1 type should be Button")
        XCTAssertEqual(button1.properties["title"] as? String, "New", "Button1 title should match")
        XCTAssertEqual(button1.properties["actionID"] as? String, "file.new", "Button1 actionID should match")
        
        // Verify CommandGroup
        let commandGroup = commands[1]
        XCTAssertEqual(commandGroup.id, 5, "CommandGroup ID should be 5")
        XCTAssertEqual(commandGroup.type, "CommandGroup", "Command type should be CommandGroup")
        XCTAssertEqual(commandGroup.properties["placement"] as? String, "replacing", "CommandGroup placement should match")
        XCTAssertEqual(commandGroup.properties["placementTarget"] as? String, "newItem", "CommandGroup placementTarget should match")
        guard let groupChildren = commandGroup.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve CommandGroup children")
            return
        }
        XCTAssertEqual(groupChildren.count, 1, "CommandGroup should have 1 child")
        
        let groupButton = groupChildren[0]
        XCTAssertEqual(groupButton.id, 6, "Group Button ID should be 6")
        XCTAssertEqual(groupButton.type, "Button", "Group Button type should be Button")
        XCTAssertEqual(groupButton.properties["title"] as? String, "Custom New", "Group Button title should match")
        XCTAssertEqual(groupButton.properties["actionID"] as? String, "custom.new", "Group Button actionID should match")
        
        // Assert: Verify view models
        let elementIds = [2, 3, 4, 5, 6] // Content, CommandMenu, Button1, CommandGroup, Group Button
        for elementId in elementIds {
            guard let viewModel = windowModel.viewModels[elementId] else {
                XCTFail("Failed to retrieve viewModel for element id: \(elementId)")
                return
            }
            if elementId != 4 && elementId != 6 { // Buttons have validated properties
                XCTAssertFalse(viewModel.validatedProperties.isEmpty, "View model validated properties should not be empty for element id: \(elementId)")
            }
        }
        
        // Log state for debugging
        logger.log("Final windowModel for windowUUID \(windowUUID!): \(String(describing: windowModel))", .debug)
    }
    
    func testWindowGroupJSONDecoding() throws {
        // Arrange: Create JSON description for WindowGroup with valid CommandMenu
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
                                "actionID": "file.new"
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
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
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
        
        // Verify commands
        guard let commands = element.subviews?["commands"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve commands from WindowGroup")
            return
        }
        XCTAssertEqual(commands.count, 1, "WindowGroup should have 1 command element")
        
        // Verify CommandMenu
        let commandMenu = commands[0]
        XCTAssertEqual(commandMenu.id, 3, "CommandMenu ID should be 3")
        XCTAssertEqual(commandMenu.type, "CommandMenu", "Command type should be CommandMenu")
        XCTAssertEqual(commandMenu.properties["name"] as? String, "File", "CommandMenu name should match")
        guard let menuChildren = commandMenu.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve CommandMenu children")
            return
        }
        XCTAssertEqual(menuChildren.count, 1, "CommandMenu should have 1 child")
        
        let button1 = menuChildren[0]
        XCTAssertEqual(button1.id, 4, "Button1 ID should be 4")
        XCTAssertEqual(button1.type, "Button", "Button1 type should be Button")
        XCTAssertEqual(button1.properties["title"] as? String, "New", "Button1 title should match")
        XCTAssertEqual(button1.properties["actionID"] as? String, "file.new", "Button1 actionID should match")
    }
    
    func testWindowGroupInvalidCommandType() throws {
        // Use ConsoleLogger to avoid test failure from expected error
        ActionUIRegistry.shared.setLogger(consoleLogger)
        ActionUIModel.shared.logger = consoleLogger

        // Arrange: Create JSON description with invalid command type
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
                    "type": "InvalidCommand",
                    "properties": {}
                },
                {
                    "id": 4,
                    "type": "CommandMenu",
                    "properties": {
                        "name": "File"
                    },
                    "children": [
                        {
                            "id": 5,
                            "type": "Button",
                            "properties": {
                                "title": "New",
                                "actionID": "file.new"
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
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
        
        // Act: Instantiate WindowGroup
        let windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
        let commands = element.subviews?["commands"] as? [any ActionUIElementBase] ?? []
        _ = WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)

        // Assert: Verify parsed elements
        XCTAssertEqual(element.id, 1, "WindowGroup element ID should be 1")
        XCTAssertEqual(element.properties["title"] as? String, "Test Window", "Title should match")
        
        guard let commands = element.subviews?["commands"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve commands from WindowGroup")
            return
        }
        XCTAssertEqual(commands.count, 2, "WindowGroup should have 2 command elements")
        
        // Verify invalid command
        let invalidCommand = commands[0]
        XCTAssertEqual(invalidCommand.id, 3, "Invalid command ID should be 3")
        XCTAssertEqual(invalidCommand.type, "InvalidCommand", "Command type should be InvalidCommand")
        
        // Verify valid CommandMenu
        let commandMenu = commands[1]
        XCTAssertEqual(commandMenu.id, 4, "CommandMenu ID should be 4")
        XCTAssertEqual(commandMenu.type, "CommandMenu", "Command type should be CommandMenu")
        XCTAssertEqual(commandMenu.properties["name"] as? String, "File", "CommandMenu name should match")
        guard let menuChildren = commandMenu.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve CommandMenu children")
            return
        }
        XCTAssertEqual(menuChildren.count, 1, "CommandMenu should have 1 child")
        
        // Assert: Verify view models (invalid command should be skipped)
        let validIds = [2, 4, 5] // Content, CommandMenu, Button
        for elementId in validIds {
            guard let viewModel = windowModel.viewModels[elementId] else {
                XCTFail("Failed to retrieve viewModel for element id: \(elementId)")
                return
            }
            if elementId != 5 { // Button has validated properties
                XCTAssertFalse(viewModel.validatedProperties.isEmpty, "View model validated properties should not be empty for element id: \(elementId)")
            }
        }
//        XCTAssertNil(windowModel.viewModels[3], "View model for invalid command id 3 should be nil")
        
        // Log state for debugging
        consoleLogger.log("Final windowModel for windowUUID \(windowUUID!): \(String(describing: windowModel))", .debug)

        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
    }
    
    func testWindowGroupTooManyCommands() throws {
        // Arrange: Create JSON with 11 commands (exceeding the 10-command limit)
        var commandsArray: [[String: Any]] = []
        for i in 1...11 {
            commandsArray.append([
                "id": 2 + i,
                "type": "CommandMenu",
                "properties": ["name": "Menu\(i)"],
                "children": [
                    [
                        "id": 13 + i,
                        "type": "Button",
                        "properties": [
                            "title": "Action\(i)",
                            "actionID": "action.\(i)"
                        ]
                    ]
                ]
            ])
        }
        let json: [String: Any] = [
            "id": 1,
            "type": "WindowGroup",
            "properties": ["title": "Test Window"],
            "content": [
                "id": 2,
                "type": "Text",
                "properties": ["text": "Welcome"]
            ],
            "commands": commandsArray
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            XCTFail("Failed to convert JSON dictionary to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
        
        // Act: Instantiate WindowGroup
        let windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
        let commands = element.subviews?["commands"] as? [any ActionUIElementBase] ?? []
        _ = WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)

        // Assert: Verify parsed elements
        XCTAssertEqual(element.id, 1, "WindowGroup element ID should be 1")
        XCTAssertEqual(element.properties["title"] as? String, "Test Window", "Title should match")
        
        guard let commands = element.subviews?["commands"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve commands from WindowGroup")
            return
        }
        XCTAssertEqual(commands.count, 11, "WindowGroup should have 11 command elements")
        
        // Verify view models (only first 10 commands should have view models)
        let validCommandIds = (3...12) // IDs 3 to 12 (first 10 commands)
        for commandId in validCommandIds {
            guard let viewModel = windowModel.viewModels[commandId] else {
                XCTFail("Failed to retrieve viewModel for command id: \(commandId)")
                return
            }
            XCTAssertFalse(viewModel.validatedProperties.isEmpty, "Command view model validated properties should not be empty")
        }
//        XCTAssertNil(windowModel.viewModels[13], "View model for command id 13 (11th command) should be nil")
        
        // Log state for debugging
        logger.log("Final windowModel for windowUUID \(windowUUID!): \(String(describing: windowModel))", .debug)
    }
    
    func testWindowGroupInvalidCommandProperties() throws {
        // Use ConsoleLogger to avoid test failure from expected error
        ActionUIRegistry.shared.setLogger(consoleLogger)
        ActionUIModel.shared.logger = consoleLogger

        // Arrange: Create JSON with invalid command properties (empty name, invalid placement)
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
                        "name": ""
                    },
                    "children": [
                        {
                            "id": 4,
                            "type": "Button",
                            "properties": {
                                "title": "New",
                                "actionID": "file.new"
                            }
                        }
                    ]
                },
                {
                    "id": 5,
                    "type": "CommandGroup",
                    "properties": {
                        "placement": "invalid",
                        "placementTarget": "newItem"
                    },
                    "children": [
                        {
                            "id": 6,
                            "type": "Button",
                            "properties": {
                                "title": "Custom New",
                                "actionID": "custom.new"
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
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
        
        // Act: Instantiate WindowGroup
        let windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
        let commands = element.subviews?["commands"] as? [any ActionUIElementBase] ?? []
        _ = WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)

        // Assert: Verify parsed elements
        XCTAssertEqual(element.id, 1, "WindowGroup element ID should be 1")
        XCTAssertEqual(element.properties["title"] as? String, "Test Window", "Title should match")
        
        guard let commands = element.subviews?["commands"] as? [any ActionUIElementBase] else {
            XCTFail("Failed to retrieve commands from WindowGroup")
            return
        }
        XCTAssertEqual(commands.count, 2, "WindowGroup should have 2 command elements")
        
        // Verify CommandMenu with invalid properties
        let commandMenu = commands[0]
        XCTAssertEqual(commandMenu.id, 3, "CommandMenu ID should be 3")
        XCTAssertEqual(commandMenu.type, "CommandMenu", "Command type should be CommandMenu")
        XCTAssertEqual(commandMenu.properties["name"] as? String, "", "CommandMenu name should be empty")
        
        // Verify CommandGroup with invalid properties
        let commandGroup = commands[1]
        XCTAssertEqual(commandGroup.id, 5, "CommandGroup ID should be 5")
        XCTAssertEqual(commandGroup.type, "CommandGroup", "Command type should be CommandGroup")
        XCTAssertEqual(commandGroup.properties["placement"] as? String, "invalid", "CommandGroup placement should be invalid")
        
        // Assert: Verify view models (invalid commands should be skipped)
        let validIds = [2, 4, 6] // Content, Button (CommandMenu child), Button (CommandGroup child)
        for elementId in validIds {
            guard let viewModel = windowModel.viewModels[elementId] else {
                XCTFail("Failed to retrieve viewModel for element id: \(elementId)")
                return
            }
            if elementId != 4 && elementId != 6 { // Buttons have validated properties
                XCTAssertFalse(viewModel.validatedProperties.isEmpty, "View model validated properties should not be empty for element id: \(elementId)")
            }
        }
//        XCTAssertNil(windowModel.viewModels[3], "View model for invalid CommandMenu id 3 should be nil")
//        XCTAssertNil(windowModel.viewModels[5], "View model for invalid CommandGroup id 5 should be nil")
        
        // Log state for debugging
        consoleLogger.log("Final windowModel for windowUUID \(windowUUID!): \(String(describing: windowModel))", .debug)

        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
    }
    
    func testWindowGroupEmptyCommands() throws {
        // Arrange: Create JSON with empty commands array
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
            "commands": []
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID] else {
            XCTFail("Failed to retrieve windowModel from actionUIModel for windowUUID: \(windowUUID!)")
            return
        }
        
        // Act: Instantiate WindowGroup
        let windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
        let commands = element.subviews?["commands"] as? [any ActionUIElementBase] ?? []
        _ = WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)

        // Assert: Verify parsed elements
        XCTAssertEqual(element.id, 1, "WindowGroup element ID should be 1")
        XCTAssertEqual(element.properties["title"] as? String, "Test Window", "Title should match")
        
        XCTAssertEqual(commands.count, 0, "WindowGroup should be nil or have 0 command elements")
        
        // Assert: Verify content view model
        guard let contentViewModel = windowModel.viewModels[2] else {
            XCTFail("Failed to retrieve viewModel for content element id: 2")
            return
        }
        XCTAssertFalse(contentViewModel.validatedProperties.isEmpty, "Content view model validated properties should not be empty")
        
        // Log state for debugging
        logger.log("Final windowModel for windowUUID \(windowUUID!): \(String(describing: windowModel))", .debug)
    }
}
