// Sources/CommandMenu.swift
import SwiftUI

/*
 CommandMenu.swift

 Constructs a SwiftUI.CommandMenu from an ActionUIElementBase.

 Expected JSON properties:
 {
   "type": "CommandMenu",
   "id": Int, // Unique identifier
   "properties": {
     "name": String, // Required: Non-empty string for the menu title
     "role:web": String, // Optional, WEB ONLY: "account" renders this menu as the shell's account button (top-right) instead of a menu-bar entry. "account" is the only recognized value; only the FIRST account menu is used, later ones warn and are ignored. Apple and Android ignore the key.
     "systemImage:web": String // Optional, WEB ONLY: SF Symbol name for the account button's glyph, resolved through the SF-to-Material map. Read only when "role:web" is "account"; defaults to a person glyph.
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
 Example:
 {
   "type": "CommandMenu",
   "id": 8,
   "properties": {
     "name": "Test"
   },
   "children": [
     {
       "type": "Button",
       "id": 9,
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
       "id": 10
     }
   ]
 }
*/

struct CommandMenu : ActionUIPropertyValidation {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate name
        let name = validatedProperties["name"] as? String
        if let name, name.isEmpty {
            logger.log("CommandMenu name must be a non-empty string; defaulting to 'Menu'", .warning)
            validatedProperties["name"] = nil
        }
        
        return validatedProperties
    }
    
    @MainActor
    static func build(_ element: any ActionUIElementBase, windowUUID: String, properties: [String: Any], logger: any ActionUILogger) -> some SwiftUI.Commands {
        
        var name = properties["name"] as? String ?? "Menu"
        if name.isEmpty {
            logger.log("CommandMenu name must be a non-empty string; defaulting to 'Menu'", .error)
            name = "Menu"
        }
        let children = (element.subviews?["children"] as? [any ActionUIElementBase]) ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        return SwiftUI.CommandMenu(name) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
