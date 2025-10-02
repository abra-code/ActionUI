// Sources/CommandGroup.swift
import SwiftUI

/*
 CommandGroup.swift

 Constructs a SwiftUI.CommandGroup from an ActionUIElementBase.

 Expected JSON properties:
 {
   "type": "CommandGroup",
   "id": Int, // Unique identifier
   "properties": {
     "placement": String, // Optional: One of "replacing", "before", "after". Defaults to "after" if missing or invalid
     "placementTarget": String // Optional: One of "appInfo", "appSettings", "systemServices", "appVisibility", "appTermination", "newItem", "saveItem", "importExport", "printItem", "undoRedo", "pasteboard", "textEditing", "textFormatting", "toolbar", "sidebar", "windowSize", "windowList", "singleWindowList", "windowArrangement", "help". Defaults to "help" if missing or invalid
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
 }
*/

struct CommandGroup : ActionUIPropertyValidation {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate placement
        let placement = validatedProperties["placement"] as? String
        if placement == nil {
            logger.log("CommandGroup placement is missing; defaulting to 'after'", .warning)
        }
        else if !["replacing", "before", "after"].contains(placement) {
            logger.log("CommandGroup placement is invalid. It must be 'replacing', 'before', or 'after'; defaulting to 'after'", .warning)
            validatedProperties["placement"] = nil
        }
        
        // Validate placementTarget
        let placementTarget = validatedProperties["placementTarget"] as? String
        if placementTarget == nil {
            logger.log("CommandGroup placementTarget is missing; defaulting to 'help'", .warning)
        } else if !["appInfo", "appSettings", "systemServices", "appVisibility", "appTermination", "newItem", "saveItem", "importExport", "printItem", "undoRedo", "pasteboard", "textEditing", "textFormatting", "toolbar", "sidebar", "windowSize", "windowList", "singleWindowList", "windowArrangement", "help"].contains(placementTarget) {
            logger.log("CommandGroup placementTarget must be a valid CommandGroupPlacement value; defaulting to 'help'", .warning)
            validatedProperties["placementTarget"] = nil
        }
        
        return validatedProperties
    }
    
    @MainActor
    static func build(_ element: any ActionUIElementBase, windowUUID: String, properties: [String: Any], logger: any ActionUILogger) -> some SwiftUI.Commands /*SwiftUI.CommandGroup<AnyView>*/ {
        
        let placement = properties["placement"] as? String ?? "after"
        let placementTarget = properties["placementTarget"] as? String ?? "help"
        let commandGroupPlacement = placementToCommandGroupPlacement(placement, target: placementTarget, logger: logger) ?? .help
                
        let children = (element.subviews?["children"] as? [any ActionUIElementBase]) ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        switch placement {
        case "replacing":
            return SwiftUI.CommandGroup(replacing: commandGroupPlacement) {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        case "before":
            return SwiftUI.CommandGroup(before: commandGroupPlacement) {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        case "after":
            return SwiftUI.CommandGroup(after: commandGroupPlacement) {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        default:
            return SwiftUI.CommandGroup(after: commandGroupPlacement) {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
           }
        }
    }
    
    static func placementToCommandGroupPlacement(_ placement: String, target: String, logger: any ActionUILogger) -> CommandGroupPlacement? {
        switch target {
        case "appInfo": return .appInfo
        case "appSettings": return .appSettings
        case "systemServices": return .systemServices
        case "appVisibility": return .appVisibility
        case "appTermination": return .appTermination
        case "newItem": return .newItem
        case "saveItem": return .saveItem
        case "importExport": return .importExport
        case "printItem": return .printItem
        case "undoRedo": return .undoRedo
        case "pasteboard": return .pasteboard
        case "textEditing": return .textEditing
        case "textFormatting": return .textFormatting
        case "toolbar": return .toolbar
        case "sidebar": return .sidebar
        case "windowSize": return .windowSize
        case "windowList":
            #if os(macOS)
            return .windowList
            #else
            return .windowArrangement
            #endif
        case "singleWindowList":
            #if os(macOS)
            return .singleWindowList
            #else
            return .windowArrangement
            #endif
        case "windowArrangement": return .windowArrangement
        case "help": return .help
        default:
            logger.log("Invalid placementTarget: \(target)", .warning)
            return nil
        }
    }
}
