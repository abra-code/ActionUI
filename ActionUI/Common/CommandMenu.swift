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

struct CommandMenu {
    static func validateProperties(_ properties: [String: Any], logger: any ActionUILogger) -> [String: Any] {
        let validatedProperties = properties
        
        // Validate name
        guard let name = validatedProperties["name"] as? String, !name.isEmpty else {
            logger.log("CommandMenu name must be a non-empty string; ignoring properties", .error)
            return [:]
        }
        
        return validatedProperties
    }
    
    @MainActor
    static func build(_ element: any ActionUIElementBase, windowUUID: String, properties: [String: Any], logger: any ActionUILogger) -> SwiftUI.CommandMenu<AnyView> {
        guard element.type == "CommandMenu" else {
            logger.log("Element type must be CommandMenu, got \(element.type)", .error)
            return SwiftUI.CommandMenu("Invalid") { AnyView(SwiftUI.EmptyView()) }
        }
        
        guard let name = properties["name"] as? String, !name.isEmpty else {
            logger.log("CommandMenu requires a valid name in validated properties", .error)
            return SwiftUI.CommandMenu("Invalid") { AnyView(SwiftUI.EmptyView()) }
        }
        
        let children = (element.subviews?["children"] as? [any ActionUIElementBase]) ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        return SwiftUI.CommandMenu(name) {
            AnyView(
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
}
