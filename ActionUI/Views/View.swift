// Sources/Views/View.swift
/*
 Sample JSON for View (base structure for all views):
 {
   "type": "View",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "padding": 10.0,      // Optional: Double for padding around the view
     "hidden": false,      // Optional: Boolean to hide the view
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue") for text or content tint
     "font": "body",       // Optional: SwiftUI font role (e.g., "title", "body") for text content
     "background": "white", // Optional: SwiftUI color (e.g., "red", "blue") or hex (e.g., "#FF0000") for background, applied via .background() modifier (color only for now)
     "frame": {            // Optional: Dictionary defining view size (e.g., {"width": 100, "height": 100})
       "width": 100.0,     // Optional: Double for width
       "height": 100.0     // Optional: Double for height
     },
     "opacity": 1.0,       // Optional: Double (0.0 to 1.0) for view transparency
     "cornerRadius": 5.0,  // Optional: Double for rounded corners
     "actionID": "view.action", // Optional: String for action identifier, applicable to all elements with action handlers
     "disabled": false     // Optional: Boolean to disable user interaction
   }
   // Note: These properties serve as the baseline for all views. All additional properties/modifiers inherited from SwiftUI's View protocol are supported and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). Only view/control-specific properties are listed in derived views.
 }
*/

import SwiftUI

struct View: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if !(properties["padding"] is Double?), properties["padding"] != nil {
            logger.log("Invalid type for padding: expected Double, got \(type(of: properties["padding"]!)), ignoring", .warning)
            validatedProperties["padding"] = nil
        }
        
        if !(properties["hidden"] is Bool?), properties["hidden"] != nil {
            logger.log("Invalid type for hidden: expected Bool, got \(type(of: properties["hidden"]!)), ignoring", .warning)
            validatedProperties["hidden"] = nil
        }
        
        if !(properties["foregroundColor"] is String?), properties["foregroundColor"] != nil {
            logger.log("Invalid type for foregroundColor: expected String, got \(type(of: properties["foregroundColor"]!)), ignoring", .warning)
            validatedProperties["foregroundColor"] = nil
        }
        
        if !(properties["font"] is String?), properties["font"] != nil {
            logger.log("Invalid type for font: expected String, got \(type(of: properties["font"]!)), ignoring", .warning)
            validatedProperties["font"] = nil
        }
        
        if !(properties["background"] is String?), properties["background"] != nil {
            logger.log("Invalid type for background: expected String, got \(type(of: properties["background"]!)), ignoring", .warning)
            validatedProperties["background"] = nil
        }
        
        if let frame = properties["frame"] as? [String: Any] {
            if !(frame["width"] is Double) || !(frame["height"] is Double) {
                logger.log("Invalid frame: must contain both width and height as Double, ignoring", .warning)
                validatedProperties["frame"] = nil
            }
        } else if properties["frame"] != nil {
            logger.log("Invalid type for frame: expected dictionary, got \(type(of: properties["frame"]!)), ignoring", .warning)
            validatedProperties["frame"] = nil
        }
        
        if let opacity = properties["opacity"] as? Double {
            if !(0.0...1.0).contains(opacity) {
                logger.log("Invalid opacity: must be between 0.0 and 1.0, ignoring", .warning)
                validatedProperties["opacity"] = nil
            }
        } else if properties["opacity"] != nil {
            logger.log("Invalid type for opacity: expected Double, got \(type(of: properties["opacity"]!)), ignoring", .warning)
            validatedProperties["opacity"] = nil
        }
        
        if !(properties["cornerRadius"] is Double?), properties["cornerRadius"] != nil {
            logger.log("Invalid type for cornerRadius: expected Double, got \(type(of: properties["cornerRadius"]!)), ignoring", .warning)
            validatedProperties["cornerRadius"] = nil
        }
        
        if !(properties["actionID"] is String?), properties["actionID"] != nil {
            logger.log("Invalid type for actionID: expected String, got \(type(of: properties["actionID"]!)), ignoring", .warning)
            validatedProperties["actionID"] = nil
        }
        
        if !(properties["disabled"] is Bool?), properties["disabled"] != nil {
            logger.log("Invalid type for disabled: expected Bool, got \(type(of: properties["disabled"]!)), ignoring", .warning)
            validatedProperties["disabled"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        // View is never instantiated directly; return EmptyView as a fallback
        return SwiftUI.EmptyView()
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        
        if let padding = properties["padding"] as? Double {
            modifiedView = modifiedView.padding(CGFloat(padding))
        } else if let padding = properties["padding"] as? [String: Double] {
            modifiedView = modifiedView.padding(EdgeInsets(
                top: CGFloat(padding["top"] ?? 0),
                leading: CGFloat(padding["leading"] ?? 0),
                bottom: CGFloat(padding["bottom"] ?? 0),
                trailing: CGFloat(padding["trailing"] ?? 0)
            ))
        }
        
        if let font = properties["font"] as? String {
            modifiedView = modifiedView.font(FontHelper.resolveFont(font))
        }
        
        if let foregroundColor = properties["foregroundColor"] as? String, let resolvedColor = ColorHelper.resolveColor(foregroundColor) {
            modifiedView = modifiedView.foregroundColor(resolvedColor)
        }
        
        if let disabled = properties["disabled"] as? Bool {
            modifiedView = modifiedView.disabled(disabled)
        }
        
        if properties["hidden"] as? Bool == true {
            modifiedView = modifiedView.hidden()
        }
        
        if let background = properties["background"] as? String, let color = ColorHelper.resolveColor(background) {
            modifiedView = modifiedView.background(color)
        }
        
        if let frame = properties["frame"] as? [String: Any],
           let width = frame["width"] as? Double,
           let height = frame["height"] as? Double {
            modifiedView = modifiedView.frame(width: CGFloat(width), height: CGFloat(height))
        }
        
        if let opacity = properties["opacity"] as? Double, (0.0...1.0).contains(opacity) {
            modifiedView = modifiedView.opacity(opacity)
        }
        
        if let cornerRadius = properties["cornerRadius"] as? Double {
            modifiedView = modifiedView.cornerRadius(CGFloat(cornerRadius))
        }
        
        return modifiedView
    }
}
