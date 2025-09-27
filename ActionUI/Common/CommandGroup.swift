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
        let validatedProperties = properties
        
        // Validate placement
        guard let placement = validatedProperties["placement"] as? String,
              ["replacing", "before", "after"].contains(placement) else {
            logger.log("CommandGroup placement must be 'replacing', 'before', or 'after'; ignoring properties", .error)
            return [:]
        }
        
        // Validate placementTarget
        guard let placementTarget = validatedProperties["placementTarget"] as? String,
              ["appInfo", "appSettings", "systemServices", "appVisibility", "appTermination", "newItem", "saveItem", "importExport", "printItem", "undoRedo", "pasteboard", "textEditing", "textFormatting", "toolbar", "sidebar", "windowSize", "windowList", "singleWindowList", "windowArrangement", "help"].contains(placementTarget) else {
            logger.log("CommandGroup placementTarget must be a valid CommandGroupPlacement value; ignoring properties", .error)
            return [:]
        }
        
        return validatedProperties
    }
    
    @MainActor
    static func build(_ element: any ActionUIElementBase, windowUUID: String, properties: [String: Any], logger: any ActionUILogger) -> SwiftUI.CommandGroup<AnyView> {
        guard element.type == "CommandGroup" else {
            logger.log("Element type must be CommandGroup, got \(element.type)", .error)
            return SwiftUI.CommandGroup(replacing: .help) { AnyView(SwiftUI.EmptyView()) }
        }
        
        guard let placement = properties["placement"] as? String,
              let placementTarget = properties["placementTarget"] as? String,
              let commandGroupPlacement = placementToCommandGroupPlacement(placement, target: placementTarget, logger: logger) else {
            logger.log("CommandGroup requires valid placement and placementTarget in properties", .error)
            return SwiftUI.CommandGroup(replacing: .help) { AnyView(SwiftUI.EmptyView()) }
        }
        
        let children = (element.subviews?["children"] as? [any ActionUIElementBase]) ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        switch placement {
        case "replacing":
            return SwiftUI.CommandGroup(replacing: commandGroupPlacement) {
                AnyView(
                    ForEach(children, id: \.id) { child in
                        if let childModel = windowModel?.viewModels[child.id] {
                            ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                        }
                    }
                )
            }
        case "before":
            return SwiftUI.CommandGroup(before: commandGroupPlacement) {
                AnyView(
                    ForEach(children, id: \.id) { child in
                        if let childModel = windowModel?.viewModels[child.id] {
                            ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                        }
                    }
                )
            }
        case "after":
            return SwiftUI.CommandGroup(after: commandGroupPlacement) {
                AnyView(
                    ForEach(children, id: \.id) { child in
                        if let childModel = windowModel?.viewModels[child.id] {
                            ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                        }
                    }
                )
            }
        default:
            return SwiftUI.CommandGroup(replacing: .help) { AnyView(SwiftUI.EmptyView()) }
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
