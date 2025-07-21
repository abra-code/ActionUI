/*
 Sample JSON for View (base structure for all views):
 {
   "type": "View",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "padding": 10.0,      // Optional: CGFloat for padding around the view
     "hidden": false,      // Optional: Boolean to hide the view
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue") for text or content tint
     "font": "body",       // Optional: SwiftUI font role (e.g., "title", "body") for text content
     "background": "white", // Optional: SwiftUI color (e.g., "red", "blue") or hex (e.g., "#FF0000") for background, applied via .background() modifier (color only for now)
     "frame": {            // Optional: Dictionary defining view size (e.g., {"width": 100, "height": 100})
       "width": 100.0,     // Optional: CGFloat for width
       "height": 100.0     // Optional: CGFloat for height
     },
     "opacity": 1.0,       // Optional: Float (0.0 to 1.0) for view transparency
     "cornerRadius": 5.0,  // Optional: CGFloat for rounded corners
     "actionID": "view.action", // Optional: String for action identifier, applicable to all elements with action handlers
     "disabled": false     // Optional: Boolean to disable user interaction
   }
   // Note: These properties serve as the baseline for all views. All additional properties/modifiers inherited from SwiftUI's View protocol are supported and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). Only view/control-specific properties are listed in derived views.
 }
*/

import SwiftUI

struct View: ActionUIViewConstruction {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        if let padding = properties["padding"] as? CGFloat {
            validatedProperties["padding"] = padding
        } else if properties["padding"] != nil {
            print("Warning: View padding must be a CGFloat; ignoring")
            validatedProperties["padding"] = nil
        }
        
        if let hidden = properties["hidden"] as? Bool {
            validatedProperties["hidden"] = hidden
        } else if properties["hidden"] != nil {
            print("Warning: View hidden must be a Boolean; ignoring")
            validatedProperties["hidden"] = nil
        }
        
        if let foregroundColor = properties["foregroundColor"] as? String {
            validatedProperties["foregroundColor"] = foregroundColor
        } else if properties["foregroundColor"] != nil {
            print("Warning: View foregroundColor must be a string; ignoring")
            validatedProperties["foregroundColor"] = nil
        }
        
        if let font = properties["font"] as? String {
            validatedProperties["font"] = font
        } else if properties["font"] != nil {
            print("Warning: View font must be a string; ignoring")
            validatedProperties["font"] = nil
        }
        
        if let background = properties["background"] as? String {
            validatedProperties["background"] = background
        } else if properties["background"] != nil {
            print("Warning: View background must be a string; ignoring")
            validatedProperties["background"] = nil
        }
        
        if let frame = properties["frame"] as? [String: Any] {
            var validatedFrame: [String: Any] = [:]
            if let width = frame["width"] as? CGFloat {
                validatedFrame["width"] = width
            } else if frame["width"] != nil {
                print("Warning: View frame width must be a CGFloat; ignoring")
            }
            if let height = frame["height"] as? CGFloat {
                validatedFrame["height"] = height
            } else if frame["height"] != nil {
                print("Warning: View frame height must be a CGFloat; ignoring")
            }
            if !validatedFrame.isEmpty {
                validatedProperties["frame"] = validatedFrame
            }
        } else if properties["frame"] != nil {
            print("Warning: View frame must be a dictionary; ignoring")
            validatedProperties["frame"] = nil
        }
        
        if let opacity = properties["opacity"] as? Float {
            if (0.0...1.0).contains(opacity) {
                validatedProperties["opacity"] = opacity
            } else {
                print("Warning: View opacity must be between 0.0 and 1.0; ignoring")
                validatedProperties["opacity"] = nil
            }
        } else if properties["opacity"] != nil {
            print("Warning: View opacity must be a Float; ignoring")
            validatedProperties["opacity"] = nil
        }
        
        if let cornerRadius = properties["cornerRadius"] as? CGFloat {
            validatedProperties["cornerRadius"] = cornerRadius
        } else if properties["cornerRadius"] != nil {
            print("Warning: View cornerRadius must be a CGFloat; ignoring")
            validatedProperties["cornerRadius"] = nil
        }
        
        if let actionID = properties["actionID"] as? String {
            validatedProperties["actionID"] = actionID
        } else if properties["actionID"] != nil {
            print("Warning: View actionID must be a string; ignoring")
            validatedProperties["actionID"] = nil
        }
        
        if let disabled = properties["disabled"] as? Bool {
            validatedProperties["disabled"] = disabled
        } else if properties["disabled"] != nil {
            print("Warning: View disabled must be a Boolean; ignoring")
            validatedProperties["disabled"] = nil
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        // View is never instantiated directly; return EmptyView as a fallback
        return AnyView(EmptyView())
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        
        if let padding = properties["padding"] as? CGFloat {
            modifiedView = AnyView(modifiedView.padding(padding))
        } else if let padding = properties["padding"] as? [String: CGFloat] {
            modifiedView = AnyView(modifiedView.padding(EdgeInsets(
                top: padding["top"] ?? 0,
                leading: padding["leading"] ?? 0,
                bottom: padding["bottom"] ?? 0,
                trailing: padding["trailing"] ?? 0
            )))
        }
        
        if let font = properties["font"] as? String {
            modifiedView = AnyView(modifiedView.font(FontHelper.resolveFont(font)))
        }
        
        if let foregroundColor = properties["foregroundColor"], let resolvedColor = ColorHelper.resolveColor(foregroundColor) {
            modifiedView = AnyView(modifiedView.foregroundColor(resolvedColor))
        }
        
        if let disabled = properties["disabled"] as? Bool {
            modifiedView = AnyView(modifiedView.disabled(disabled))
        }
        
        if properties["hidden"] as? Bool == true {
            modifiedView = AnyView(modifiedView.hidden())
        }
        
        if let background = properties["background"] as? String, let color = ColorHelper.resolveColor(background) {
            modifiedView = AnyView(modifiedView.background(color))
        }
        
        if let frame = properties["frame"] as? [String: Any] {
            let width = frame["width"] as? CGFloat
            let height = frame["height"] as? CGFloat
            modifiedView = AnyView(modifiedView.frame(width: width, height: height))
        }
        
        if let opacity = properties["opacity"] as? Float, (0.0...1.0).contains(opacity) {
            modifiedView = AnyView(modifiedView.opacity(Double(opacity)))
        }
        
        if let cornerRadius = properties["cornerRadius"] as? CGFloat {
            modifiedView = AnyView(modifiedView.cornerRadius(cornerRadius))
        }
        
        return modifiedView
    }
}
