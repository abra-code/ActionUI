// Sources/Views/View.swift
/*
 Sample JSON for View (base structure for all views):
 {
   "type": "View",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "padding": 10.0,      // Optional: Double for padding around the view or EdgeInsets dictionary {"top": 10, "bottom": 10, "leading": 5, "trailing": 5}
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
        
        // Validate padding
        if (properties.cgFloat(forKey: "padding") == nil) && !(properties["padding"] is [String: Any]?), properties["padding"] != nil {
            logger.log("Invalid type for padding: expected Double or [String: Any], got \(type(of: properties["padding"]!)), ignoring", .warning)
            validatedProperties["padding"] = nil
        }
        
        // Validate hidden
        if !(properties["hidden"] is Bool?), properties["hidden"] != nil {
            logger.log("Invalid type for hidden: expected Bool, got \(type(of: properties["hidden"]!)), ignoring", .warning)
            validatedProperties["hidden"] = nil
        }
        
        // Validate foregroundColor
        if !(properties["foregroundColor"] is String?), properties["foregroundColor"] != nil {
            logger.log("Invalid type for foregroundColor: expected String, got \(type(of: properties["foregroundColor"]!)), ignoring", .warning)
            validatedProperties["foregroundColor"] = nil
        }
        
        // Validate font
        if !(properties["font"] is String?), properties["font"] != nil {
            logger.log("Invalid type for font: expected String, got \(type(of: properties["font"]!)), ignoring", .warning)
            validatedProperties["font"] = nil
        }
        
        // Validate background
        if !(properties["background"] is String?), properties["background"] != nil {
            logger.log("Invalid type for background: expected String, got \(type(of: properties["background"]!)), ignoring", .warning)
            validatedProperties["background"] = nil
        }
        
        // Validate frame
        if let frame = validatedProperties["frame"] as? [String: Any] {
            var validFrame: [String: Any] = [:]
            var isValid = true
            
            if let width = frame.cgFloat(forKey: "width") {
                validFrame["width"] = width
            } else if frame["width"] != nil {
                logger.log("Invalid type for frame.width: expected Double, got \(type(of: frame["width"]!)), ignoring frame", .warning)
                isValid = false
            }
            
            if let height = frame.cgFloat(forKey: "height") {
                validFrame["height"] = height
            } else if frame["height"] != nil {
                logger.log("Invalid type for frame.height: expected Double, got \(type(of: frame["height"]!)), ignoring frame", .warning)
                isValid = false
            }
            
            if let alignment = frame["alignment"] as? String {
                let validAlignments = ["leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"]
                if validAlignments.contains(alignment) {
                    validFrame["alignment"] = alignment
                } else {
                    logger.log("Invalid frame.alignment '\(alignment)', ignoring frame", .warning)
                    isValid = false
                }
            }
            
            validatedProperties["frame"] = isValid && validFrame["width"] != nil && validFrame["height"] != nil ? validFrame : nil
        } else if validatedProperties["frame"] != nil {
            logger.log("Invalid type for frame: expected [String: Any], got \(type(of: validatedProperties["frame"]!)), ignoring", .warning)
            validatedProperties["frame"] = nil
        }
        
        // Validate opacity
        if let opacity = validatedProperties.double(forKey: "opacity") {
            if !(0.0...1.0).contains(opacity) {
                logger.log("Invalid opacity '\(opacity)': must be between 0.0 and 1.0, ignoring", .warning)
                validatedProperties["opacity"] = nil
            }
        } else if validatedProperties["opacity"] != nil {
            logger.log("Invalid type for opacity: expected Double, got \(type(of: validatedProperties["opacity"]!)), ignoring", .warning)
            validatedProperties["opacity"] = nil
        }
        
        // Validate cornerRadius
        if properties.cgFloat(forKey: "cornerRadius") == nil, properties["cornerRadius"] != nil {
            logger.log("Invalid type for cornerRadius: expected Double, got \(type(of: properties["cornerRadius"]!)), ignoring", .warning)
            validatedProperties["cornerRadius"] = nil
        }
        
        // Validate actionID
        if !(properties["actionID"] is String?), properties["actionID"] != nil {
            logger.log("Invalid type for actionID: expected String, got \(type(of: properties["actionID"]!)), ignoring", .warning)
            validatedProperties["actionID"] = nil
        }
        
        // Validate disabled
        if !(properties["disabled"] is Bool?), properties["disabled"] != nil {
            logger.log("Invalid type for disabled: expected Bool, got \(type(of: properties["disabled"]!)), ignoring", .warning)
            validatedProperties["disabled"] = nil
        }
        
        // Validate accessibility properties
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
        
        // Validate shadow
        if let shadow = validatedProperties["shadow"] as? [String: Any] {
            var validatedShadow: [String: Any] = [:]
            
            if let color = shadow["color"] as? String {
                validatedShadow["color"] = color
            } else if shadow["color"] != nil {
                logger.log("Invalid type for shadow.color: expected String, got \(type(of: shadow["color"]!)), ignoring color", .warning)
            }
            
            if let radius = shadow.cgFloat(forKey: "radius") {
                validatedShadow["radius"] = radius
            } else if shadow["radius"] != nil {
                logger.log("Invalid type for shadow.radius: expected Double, got \(type(of: shadow["radius"]!)), ignoring radius", .warning)
            }
            
            if let x = shadow.cgFloat(forKey: "x") {
                validatedShadow["x"] = x
            } else if shadow["x"] != nil {
                logger.log("Invalid type for shadow.x: expected Double, got \(type(of: shadow["x"]!)), ignoring x", .warning)
            }
            
            if let y = shadow.cgFloat(forKey: "y") {
                validatedShadow["y"] = y
            } else if shadow["y"] != nil {
                logger.log("Invalid type for shadow.y: expected Double, got \(type(of: shadow["y"]!)), ignoring y", .warning)
            }
            
            validatedProperties["shadow"] = validatedShadow.isEmpty ? nil : validatedShadow
        } else if validatedProperties["shadow"] != nil {
            logger.log("Invalid type for shadow: expected [String: Any], got \(type(of: validatedProperties["shadow"]!)), ignoring", .warning)
            validatedProperties["shadow"] = nil
        }
        
        // Validate padding dictionary
        if let padding = validatedProperties["padding"] as? [String: Any] {
            var validatedPadding: [String: Any] = [:]
            var isValid = true
            
            for edge in ["top", "bottom", "leading", "trailing"] {
                if let value = padding.cgFloat(forKey: edge) {
                    validatedPadding[edge] = value
                } else if padding[edge] != nil {
                    logger.log("Invalid type for padding.\(edge): expected Double, got \(type(of: padding[edge]!)), ignoring padding", .warning)
                    isValid = false
                }
            }
            
            validatedProperties["padding"] = isValid ? validatedPadding : nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        // View is never instantiated directly; return EmptyView as a fallback
        return SwiftUI.EmptyView()
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        
        // Do not handle actionID here; concrete views (e.g., ComboBox, DatePicker) should handle actionID in buildView with specific context (e.g., windowUUID, viewID, viewPartID)
        
        if let padding = properties["padding"] as? [String: Any] {
            modifiedView = modifiedView.padding(EdgeInsets(
                top: padding.cgFloat(forKey: "top") ?? 0.0,
                leading: padding.cgFloat(forKey: "leading") ?? 0.0,
                bottom: padding.cgFloat(forKey: "bottom") ?? 0.0,
                trailing: padding.cgFloat(forKey: "trailing") ?? 0.0
            ))
        } else if let padding = properties.cgFloat(forKey: "padding") {
            modifiedView = modifiedView.padding(padding)
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
           let width = frame.cgFloat(forKey: "width"),
           let height = frame.cgFloat(forKey: "height") {
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
            modifiedView = modifiedView.frame(width: width, height: height, alignment: alignment)
        }
        
        if let opacity = properties.double(forKey: "opacity"), (0.0...1.0).contains(opacity) {
            modifiedView = modifiedView.opacity(opacity)
        }
        
        if let cornerRadius = properties.cgFloat(forKey: "cornerRadius") {
            modifiedView = modifiedView.cornerRadius(cornerRadius)
        }
        
        if let shadow = properties["shadow"] as? [String: Any] {
            let color = ColorHelper.resolveColor(shadow["color"] as? String ?? "black") ?? .black
            let radius = shadow.cgFloat(forKey: "radius") ?? 0.0
            let x = shadow.cgFloat(forKey: "x") ?? 0
            let y = shadow.cgFloat(forKey: "y") ?? 0
            modifiedView = modifiedView.shadow(color: color, radius: radius, x: x, y: y)
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
