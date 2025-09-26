// Sources/WindowGroup.swift
import SwiftUI

/*
 WindowGroup.swift

 Constructs a SwiftUI.WindowGroup from an ActionUIElement.

 Expected JSON properties:
 {
   "type": "WindowGroup",
   "id": Int, // Unique identifier
   "properties": {
     "title": String // Required: Non-empty string for the window title
   },
   "content": {
     // Required: A single view element (e.g., VStack, Text)
     "type": String, // View type registered in ActionUIRegistry (e.g., "VStack", "Text")
     "id": Int,
     "properties": { // Properties depend on the view type
       // Example for VStack
       "alignment": String, // Optional: One of "leading", "center", "trailing"
       "spacing": Double // Optional: Spacing between children
     },
     "children": [ // Optional: Array of child views (e.g., Text for VStack)
       {
         "type": String,
         "id": Int,
         "properties": { // Properties depend on the view type
           // Example for Text
           "text": String // Required: Text content
         }
       }
     ]
   },
   "commands": [ // Optional: Array of command elements, limited to 10 root-level commands due to SwiftUI CommandsBuilder restrictions
     {
       "type": "CommandMenu",
       "id": Int,
       "properties": {
         "name": String // Required: Non-empty string for the menu title
       },
       "children": [
         // Array of child elements (e.g., Button, Divider)
         {
           "type": "Button",
           "id": Int,
           "properties": {
             "title": String, // Required: Button title
             "actionID": String, // Optional: Identifier for action dispatching
             "keyboardShortcut": { // Optional
               "key": String, // Required: Single character or special key (e.g., "return")
               "modifiers": [String] // Optional: Array of modifiers (e.g., ["command", "shift"])
             }
           }
         },
         {
           "type": "Divider",
           "id": Int,
           "properties": {} // Optional: Typically empty
         }
       ]
     },
     {
       "type": "CommandGroup",
       "id": Int,
       "properties": {
         "placement": String, // Required: One of "replacing", "before", "after"
         "placementTarget": String // Required: One of "appInfo", "appSettings", "systemServices", "appVisibility", "appTermination", "newItem", "saveItem", "importExport", "printItem", "undoRedo", "pasteboard", "textEditing", "textFormatting", "toolbar", "sidebar", "windowSize", "windowList", "singleWindowList", "windowArrangement", "help"
       },
       "children": [
         // Array of child elements (e.g., Button, Divider)
         {
           "type": "Button",
           "id": Int,
           "properties": {
             "title": String, // Required: Button title
             "actionID": String, // Optional: Identifier for action dispatching
             "keyboardShortcut": { // Optional
               "key": String, // Required: Single character or special key (e.g., "return")
               "modifiers": [String] // Optional: Array of modifiers (e.g., ["command", "shift"])
             }
           }
         },
         {
           "type": "Divider",
           "id": Int,
           "properties": {} // Optional: Typically empty
         }
       ]
     }
   ]
 }
 Example:
 {
   "type": "WindowGroup",
   "id": 1,
   "properties": {
     "title": "ActionUI Window"
   },
   "content": {
     "type": "VStack",
     "id": 2,
     "properties": {
       "alignment": "center",
       "spacing": 10.0
     },
     "children": [
       {
         "type": "Text",
         "id": 3,
         "properties": {
           "text": "Welcome to ActionUI"
         }
       }
     ]
   },
   "commands": [ // Limited to 10 root-level commands; additional commands are ignored with a warning logged
     {
       "type": "CommandGroup",
       "id": 4,
       "properties": {
         "placement": "replacing",
         "placementTarget": "newItem"
       },
       "children": [
         {
           "type": "Button",
           "id": 5,
           "properties": {
             "title": "Custom Action",
             "actionID": "custom.action",
             "keyboardShortcut": {
               "key": "n",
               "modifiers": ["command"]
             }
           }
         }
       ]
     },
     {
       "type": "CommandMenu",
       "id": 6,
       "properties": {
         "name": "Test"
       },
       "children": [
         {
           "type": "Button",
           "id": 7,
           "properties": {
             "title": "Test Something",
             "actionID": "test.something",
             "keyboardShortcut": {
               "key": "t",
               "modifiers": ["command", "shift"]
             }
           }
         },
         {
           "type": "Divider",
           "id": 8
         }
       ]
     }
   ]
 }
*/

@MainActor
struct WindowGroup: SwiftUI.Scene {
    let element: any ActionUIElement
    let windowUUID: String
    private let logger: any ActionUILogger
    
    init(element: any ActionUIElement, windowUUID: String, logger: any ActionUILogger) {
        self.element = element
        self.windowUUID = windowUUID
        self.logger = logger
    }
    
    var body: some Scene {
        let contentElement = element.subviews?["content"] as? any ActionUIElement
        let commands = element.subviews?["commands"] as? [any ActionUIElement] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        ActionUIModel.shared.windowModels[windowUUID] = windowModel
        
        let title = element.properties["title"] as? String ?? "Untitled"
        
        // Log warning if commands array exceeds 10 elements
        if commands.count > 10 {
            logger.log("WindowGroup (id: \(element.id)) has \(commands.count) commands, exceeding the limit of 10 root-level commands. Only the first 10 will be processed.", .warning)
        }
        
        // Validate command types and log warnings for invalid types
        for index in 0..<min(commands.count, 10) {
            let command = commands[index]
            if command.type != "CommandMenu" && command.type != "CommandGroup" {
                logger.log("WindowGroup (id: \(element.id)) encountered invalid command type '\(command.type)' for command id \(command.id). Skipping.", .warning)
            }
        }
        
        return SwiftUI.WindowGroup(title) {
            if let contentElement = contentElement,
               let viewModel = windowModel.viewModels[contentElement.id] {
                ActionUIView(element: contentElement, model: viewModel, windowUUID: windowUUID)
            }
        }
        .commands {
            if commands.count > 0 {
                let command = commands[0]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 1 {
                let command = commands[1]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 2 {
                let command = commands[2]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 3 {
                let command = commands[3]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 4 {
                let command = commands[4]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 5 {
                let command = commands[5]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 6 {
                let command = commands[6]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 7 {
                let command = commands[7]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 8 {
                let command = commands[8]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
            if commands.count > 9 {
                let command = commands[9]
                if command.type == "CommandMenu" {
                    let validatedProperties = CommandMenu.validateProperties(command.properties, logger: logger)
                    CommandMenu.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                } else if command.type == "CommandGroup" {
                    let validatedProperties = CommandGroup.validateProperties(command.properties, logger: logger)
                    CommandGroup.build(command, windowUUID: windowUUID, properties: validatedProperties, logger: logger)
                }
            }
        }
    }
}
