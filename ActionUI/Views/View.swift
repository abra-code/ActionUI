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
     "background": "white", // Optional: SwiftUI color (e.g., "red", "blue") or hex (e.g., "#FF0000") for background
     "frame": {            // Optional: Dictionary defining view size
       "width": 100.0,     // Optional: Double for width
       "height": 100.0,    // Optional: Double for height
       "alignment": "center" // Optional: String ("leading", "center", "trailing", etc.), defaults to "center"
     },
     "opacity": 1.0,       // Optional: Double (0.0 to 1.0) for view transparency
     "cornerRadius": 5.0,  // Optional: Double for rounded corners
     "actionID": "view.action", // Optional: String for action identifier
     "disabled": false,     // Optional: Boolean to disable user interaction
     "accessibilityLabel": "View", // Optional: Accessibility label for VoiceOver
     "accessibilityHint": "Base view", // Optional: Accessibility hint for VoiceOver
     "accessibilityHidden": false, // Optional: Boolean to hide view from VoiceOver
     "accessibilityIdentifier": "view_1", // Optional: String for UI testing identifier
     "shadow": {           // Optional: Dictionary for shadow styling
       "color": "black",   // Optional: SwiftUI color or hex, defaults to black
       "radius": 5.0,      // Optional: Double for shadow radius
       "x": 0.0,           // Optional: Double for x-offset
       "y": 2.0            // Optional: Double for y-offset
     }
   }
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
            var validFrame: [String: Any] = [:]
            var isValid = true
            if let width = frame["width"] as? Double {
                validFrame["width"] = width
            } else {
                if frame["width"] != nil {
                    logger.log("Invalid frame.width: expected Double, got \(type(of: frame["width"]!)), ignoring", .warning)
                }
                isValid = false
            }
            if let height = frame["height"] as? Double {
                validFrame["height"] = height
            } else {
                if frame["height"] != nil {
                    logger.log("Invalid frame.height: expected Double, got \(type(of: frame["height"]!)), ignoring", .warning)
                }
                isValid = false
            }
            if let alignment = frame["alignment"] as? String, ["leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"].contains(alignment) {
                validFrame["alignment"] = alignment
            } else if frame["alignment"] != nil {
                logger.log("Invalid frame.alignment: expected valid alignment string, got \(String(describing: frame["alignment"])), ignoring", .warning)
            }
            validatedProperties["frame"] = isValid ? validFrame : nil
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
        
        if !(properties["accessibilityLabel"] is String?), properties["accessibilityLabel"] != nil {
            logger.log("Invalid type for accessibilityLabel: expected String, got \(type(of: properties["accessibilityLabel"]!)), ignoring", .warning)
            validatedProperties["accessibilityLabel"] = nil
        }
        
        if !(properties["accessibilityHint"] is String?), properties["accessibilityHint"] != nil {
            logger.log("Invalid type for accessibilityHint: expected String, got \(type(of: properties["accessibilityHint"]!)), ignoring", .warning)
            validatedProperties["accessibilityHint"] = nil
        }
        
        if !(properties["accessibilityHidden"] is Bool?), properties["accessibilityHidden"] != nil {
            logger.log("Invalid type for accessibilityHidden: expected Bool, got \(type(of: properties["accessibilityHidden"]!)), ignoring", .warning)
            validatedProperties["accessibilityHidden"] = nil
        }
        
        if !(properties["accessibilityIdentifier"] is String?), properties["accessibilityIdentifier"] != nil {
            logger.log("Invalid type for accessibilityIdentifier: expected String, got \(type(of: properties["accessibilityIdentifier"]!)), ignoring", .warning)
            validatedProperties["accessibilityIdentifier"] = nil
        }
        
        if let shadow = properties["shadow"] as? [String: Any] {
            var validShadow: [String: Any] = [:]
            if let color = shadow["color"] as? String {
                if ColorHelper.resolveColor(color) != nil {
                    validShadow["color"] = color
                } else {
                    logger.log("Invalid shadow.color: expected valid color string, got \(color), ignoring", .warning)
                }
            }
            if let radius = shadow["radius"] as? Double, radius >= 0 {
                validShadow["radius"] = radius
            } else if shadow["radius"] != nil {
                logger.log("Invalid shadow.radius: expected non-negative Double, got \(String(describing: shadow["radius"])), ignoring", .warning)
            }
            if let x = shadow["x"] as? Double {
                validShadow["x"] = x
            } else if shadow["x"] != nil {
                logger.log("Invalid shadow.x: expected Double, got \(String(describing: shadow["x"])), ignoring", .warning)
            }
            if let y = shadow["y"] as? Double {
                validShadow["y"] = y
            } else if shadow["y"] != nil {
                logger.log("Invalid shadow.y: expected Double, got \(String(describing: shadow["y"])), ignoring", .warning)
            }
            validatedProperties["shadow"] = validShadow.isEmpty ? nil : validShadow
        } else if properties["shadow"] != nil {
            logger.log("Invalid type for shadow: expected dictionary, got \(type(of: properties["shadow"]!)), ignoring", .warning)
            validatedProperties["shadow"] = nil
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
            modifiedView = modifiedView.font(FontHelper.resolveFont(font, logger))
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
            let alignment = (frame["alignment"] as? String).flatMap { alignmentString -> Alignment? in
                switch alignmentString {
                case "leading": return .leading
                case "center": return .center
                case "trailing": return .trailing
                case "top": return .top
                case "bottom": return .bottom
                case "topLeading": return .topLeading
                case "topTrailing": return .topTrailing
                case "bottomLeading": return .bottomLeading
                case "bottomTrailing": return .bottomTrailing
                default: return nil
                }
            } ?? .center
            modifiedView = modifiedView.frame(width: CGFloat(width), height: CGFloat(height), alignment: alignment)
        }
        
        if let opacity = properties["opacity"] as? Double, (0.0...1.0).contains(opacity) {
            modifiedView = modifiedView.opacity(opacity)
        }
        
        if let cornerRadius = properties["cornerRadius"] as? Double {
            modifiedView = modifiedView.cornerRadius(CGFloat(cornerRadius))
        }
        
        if let shadow = properties["shadow"] as? [String: Any] {
            let color = ColorHelper.resolveColor(shadow["color"] as? String ?? "black") ?? .black
            let radius = shadow["radius"] as? Double ?? 0
            let x = shadow["x"] as? Double ?? 0
            let y = shadow["y"] as? Double ?? 0
            modifiedView = modifiedView.shadow(color: color, radius: CGFloat(radius), x: CGFloat(x), y: CGFloat(y))
        }
        
        if let accessibilityLabel = properties["accessibilityLabel"] as? String {
            modifiedView = AnyView(modifiedView).accessibilityLabel(accessibilityLabel)
        }
        
        if let accessibilityHint = properties["accessibilityHint"] as? String {
            modifiedView = AnyView(modifiedView).accessibilityHint(accessibilityHint)
        }
        
        if let accessibilityHidden = properties["accessibilityHidden"] as? Bool {
            modifiedView = AnyView(modifiedView).accessibilityHidden(accessibilityHidden)
        }
        
        if let accessibilityIdentifier = properties["accessibilityIdentifier"] as? String {
            modifiedView = AnyView(modifiedView).accessibilityIdentifier(accessibilityIdentifier)
        }
        
        return modifiedView
    }
}
