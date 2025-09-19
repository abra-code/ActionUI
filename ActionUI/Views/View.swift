// Sources/Views/View.swift
/*
 Sample JSON for View (base structure for all views):
 {
   "type": "View",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "padding": 10.0,      // Optional: Double for padding around the view, string "default" or EdgeInsets dictionary {"top": 10, "bottom": 10, "leading": 5, "trailing": 5}
     "hidden": false,      // Optional: Boolean to hide the view
     "foregroundStyle": "blue", // Optional: SwiftUI color (e.g., "red", "blue") or semantic style for text/content tint, resolved via foregroundStyle
     "font": "body",       // Optional: SwiftUI font role (e.g., "title", "body") for text content
     "background": "white", // Optional: SwiftUI color (e.g., "red", "blue"), hex (e.g., "#FF0000"), or semantic style for background, resolved via background
     "frame": {            // Optional: Dictionary defining view size
       "width": 100.0,     // Required: Double for width
       "height": 100.0,    // Required: Double for height
       "alignment": "center" // Optional: String ("leading", "center", "trailing", etc.), defaults to "center"
     },
     "offset": {           // Optional: Dictionary for relative positioning
       "x": 10.0,          // Optional: Double for horizontal offset
       "y": -5.0           // Optional: Double for vertical offset
     },
     "opacity": 1.0,       // Optional: Double (0.0 to 1.0) for view transparency
     "cornerRadius": 5.0,  // Optional: Double for rounded corners
     "actionID": "view.action", // Optional: String for action identifier
     "valueChangeActionID": "view.valueChanged", // Optional: String for action triggered on any value change initiated by user
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

 NOTE:
 Supported semantic styles for foregroundStyle/background:
   - "background", "foreground", "primary", "secondary", "tertiary", "quaternary", "separator", "placeholder"
 Supported named colors:
   - "red", "blue", "green", "yellow", "orange", "purple", "pink", "mint", "teal", "cyan", "indigo", "brown", "gray", "black", "white", "clear", "accentcolor"
 You can also use hex color strings (e.g., "#FF0000", "#FF000080")
*/

import SwiftUI

struct View: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate padding
        if (properties.cgFloat(forKey: "padding") == nil) && !(properties["padding"] is [String: Any]?) && !(properties["padding"] is String),
           properties["padding"] != nil {
            logger.log("Invalid type for padding: expected Double, String or [String: Any], got \(type(of: properties["padding"]!)), ignoring", .warning)
            validatedProperties["padding"] = nil
        } else if let padding = properties["padding"] as? String,
                  padding.lowercased() != "default" {
            logger.log("padding String must be 'default', got \(padding), ignoring", .warning)
            validatedProperties["padding"] = nil
        }
        
        // Validate hidden
        if !(properties["hidden"] is Bool?), properties["hidden"] != nil {
            logger.log("Invalid type for hidden: expected Bool, got \(type(of: properties["hidden"]!)), ignoring", .warning)
            validatedProperties["hidden"] = nil
        }
        
        // Validate foregroundStyle
        if !(properties["foregroundStyle"] is String?), properties["foregroundStyle"] != nil {
            logger.log("Invalid type for foregroundStyle: expected String, \(type(of: properties["foregroundStyle"]!)), ignoring", .warning)
            validatedProperties["foregroundStyle"] = nil
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
            } else {
                if frame["width"] != nil {
                    logger.log("Invalid type for frame.width: expected Double, got \(type(of: frame["width"]!)), ignoring", .warning)
                }
                isValid = false
            }
            
            if let height = frame.cgFloat(forKey: "height") {
                validFrame["height"] = height
            } else {
                if frame["height"] != nil {
                    logger.log("Invalid type for frame.height: expected Double, got \(type(of: frame["height"]!)), ignoring", .warning)
                }
                isValid = false
            }
            
            if let alignment = frame["alignment"] as? String {
                let validAlignments = ["leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"]
                if validAlignments.contains(alignment) {
                    validFrame["alignment"] = alignment
                } else {
                    if frame["alignment"] != nil {
                        logger.log("Invalid value for frame.alignment: expected one of \(validAlignments), got \(alignment), ignoring", .warning)
                    }
                    isValid = false
                }
            }
            
            if isValid {
                validatedProperties["frame"] = validFrame
            } else {
                logger.log("Invalid frame dictionary, ignoring", .warning)
                validatedProperties["frame"] = nil
            }
        } else if validatedProperties["frame"] != nil {
            logger.log("Invalid type for frame: expected [String: Any], got \(type(of: validatedProperties["frame"]!)), ignoring", .warning)
            validatedProperties["frame"] = nil
        }
        
        // Validate offset
        if let offset = validatedProperties["offset"] as? [String: Any] {
            var validOffset: [String: Any] = [:]
            var isValid = true
            
            if let x = offset.cgFloat(forKey: "x") {
                validOffset["x"] = x
            } else if offset["x"] != nil {
                logger.log("Invalid type for offset.x: expected Double, got \(type(of: offset["x"]!)), ignoring", .warning)
                isValid = false
            }
            
            if let y = offset.cgFloat(forKey: "y") {
                validOffset["y"] = y
            } else if offset["y"] != nil {
                logger.log("Invalid type for offset.y: expected Double, got \(type(of: offset["y"]!)), ignoring", .warning)
                isValid = false
            }
            
            if isValid, !validOffset.isEmpty {
                validatedProperties["offset"] = validOffset
            } else {
                logger.log("Invalid offset dictionary, ignoring", .warning)
                validatedProperties["offset"] = nil
            }
        } else if validatedProperties["offset"] != nil {
            logger.log("Invalid type for offset: expected [String: Any], got \(type(of: validatedProperties["offset"]!)), ignoring", .warning)
            validatedProperties["offset"] = nil
        }
        
        // Validate opacity
        if let opacity = properties.double(forKey: "opacity") {
            if (0.0...1.0).contains(opacity) {
                // No reassignment needed; opacity is already valid in properties
            } else {
                logger.log("Invalid value for opacity: expected Double between 0.0 and 1.0, got \(opacity), ignoring", .warning)
                validatedProperties["opacity"] = nil
            }
        } else if properties["opacity"] != nil {
            logger.log("Invalid type for opacity: expected Double, got \(type(of: properties["opacity"]!)), ignoring", .warning)
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
        
        // Validate valueChangeActionID
        if !(properties["valueChangeActionID"] is String?), properties["valueChangeActionID"] != nil {
            logger.log("Invalid type for valueChangeActionID: expected String, got \(type(of: properties["valueChangeActionID"]!)), ignoring", .warning)
            validatedProperties["valueChangeActionID"] = nil
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
        if let shadow = properties["shadow"] as? [String: Any] {
            var validShadow: [String: Any] = [:]
            var isValid = true
            
            if let color = shadow["color"] as? String {
                validShadow["color"] = color
            } else if shadow["color"] != nil {
                logger.log("Invalid type for shadow.color: expected String, got \(type(of: shadow["color"]!)), using default black", .warning)
                validShadow["color"] = "black"
            }
            
            if let radius = shadow.cgFloat(forKey: "radius") {
                validShadow["radius"] = radius
            } else if shadow["radius"] != nil {
                logger.log("Invalid type for shadow.radius: expected Double, got \(type(of: shadow["radius"]!)), ignoring", .warning)
                isValid = false
            }
            
            if let x = shadow.cgFloat(forKey: "x") {
                validShadow["x"] = x
            } else if shadow["x"] != nil {
                logger.log("Invalid type for shadow.x: expected Double, got \(type(of: shadow["x"]!)), ignoring", .warning)
                isValid = false
            }
            
            if let y = shadow.cgFloat(forKey: "y") {
                validShadow["y"] = y
            } else if shadow["y"] != nil {
                logger.log("Invalid type for shadow.y: expected Double, got \(type(of: shadow["y"]!)), ignoring", .warning)
                isValid = false
            }
            
            if isValid, !validShadow.isEmpty {
                validatedProperties["shadow"] = validShadow
            } else {
                logger.log("Invalid shadow dictionary, ignoring", .warning)
                validatedProperties["shadow"] = nil
            }
        } else if properties["shadow"] != nil {
            logger.log("Invalid type for shadow: expected [String: Any], got \(type(of: properties["shadow"]!)), ignoring", .warning)
            validatedProperties["shadow"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        SwiftUI.EmptyView()
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
        } else if let padding = properties["padding"] as? String,
                  padding.lowercased() == "default" {
            modifiedView = modifiedView.padding()
        }
        
        if let font = properties["font"] as? String {
            modifiedView = modifiedView.font(FontHelper.resolveFont(font, logger))
        }
        
        // Use foregroundStyle with resolveShapeStyle
        if let foregroundStyle = properties["foregroundStyle"] as? String, let style = ColorHelper.resolveShapeStyle(foregroundStyle) {
            modifiedView = modifiedView.foregroundStyle(style)
        }
        
        if let disabled = properties["disabled"] as? Bool {
            modifiedView = modifiedView.disabled(disabled)
        }
        
        if properties["hidden"] as? Bool == true {
            modifiedView = modifiedView.hidden()
        }
        
        // Use background with resolveShapeStyle
        if let background = properties["background"] as? String, let style = ColorHelper.resolveShapeStyle(background) {
            modifiedView = modifiedView.background(style)
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
        
        if let offset = properties["offset"] as? [String: Any] {
            let x = offset.cgFloat(forKey: "x") ?? 0.0
            let y = offset.cgFloat(forKey: "y") ?? 0.0
            modifiedView = modifiedView.offset(x: x, y: y)
            logger.log("Applied offset: x=\(x), y=\(y)", .debug)
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
            let x = shadow.cgFloat(forKey: "x") ?? 0.0
            let y = shadow.cgFloat(forKey: "y") ?? 0.0
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
