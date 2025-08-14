/*
 Sample JSON for Image:
 {
   "type": "Image",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "systemName": "star.fill",  // Optional: String for SF Symbol
     "name": "customImage",      // Optional: String for asset catalog image name
     "filePath": "/path/to/image.jpg", // Optional: String for local file path
     "resizable": true,          // Optional: Boolean to make image resizable, defaults to true
     "scaleMode": "fit",         // Optional: String ("fit" or "fill") for scaling mode, defaults to "fit"
   }
   // Note: These properties are specific to Image. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: To enable scrolling, wrap Image in a ScrollView manually, e.g.:
   // {
   //   "type": "ScrollView",
   //   "children": [
   //     {
   //       "type": "Image",
   //       "properties": { ... }
   //     }
   //   ]
   // }
 }
*/

import SwiftUI
import UniformTypeIdentifiers

struct Image: ActionUIViewConstruction {
    // Design decision: Defines valueType as Void since Image is a static view with no interactive state
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["systemName"] == nil && validatedProperties["name"] == nil && validatedProperties["filePath"] == nil {
            print("Warning: Image requires one of 'systemName', 'name', or 'filePath'; defaulting to empty image")
            validatedProperties["systemName"] = "photo"
        }
        
        if validatedProperties["resizable"] == nil {
            validatedProperties["resizable"] = true
        } else if let resizable = validatedProperties["resizable"] as? Bool {
            validatedProperties["resizable"] = resizable
        } else {
            print("Warning: Image resizable must be a boolean; defaulting to true")
            validatedProperties["resizable"] = true
        }
        
        if let scaleMode = validatedProperties["scaleMode"] as? String, !["fit", "fill"].contains(scaleMode) {
            print("Warning: Image scaleMode '\(scaleMode)' invalid; defaulting to 'fit'")
            validatedProperties["scaleMode"] = "fit"
        }
        if validatedProperties["scaleMode"] == nil {
            validatedProperties["scaleMode"] = "fit"
        }
        
        if let filePath = validatedProperties["filePath"] as? String {
            let pathExtension = URL(fileURLWithPath: filePath).pathExtension
            if let uti = UTType(filenameExtension: pathExtension),
               !uti.conforms(to: .image) && !uti.conforms(to: .pdf) {
                print("Warning: Image filePath '\(filePath)' is not an image or PDF; ignoring")
                validatedProperties["filePath"] = nil
            }
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        var image: SwiftUI.Image? = nil
        if let systemName = properties["systemName"] as? String {
            image = SwiftUI.Image(systemName: systemName)
        } else if let name = properties["name"] as? String {
            image = SwiftUI.Image(name)
        } else if let filePath = properties["filePath"] as? String {
            image = SwiftUI.Image(filePath)
        }
        
        return image ?? SwiftUI.Image(systemName: "photo")
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        if let resizable = properties["resizable"] as? Bool, resizable {
            let scaleMode = (properties["scaleMode"] as? String) ?? "fit"
            if var imageView: SwiftUI.Image = view as? SwiftUI.Image {
                return imageView.resizable().aspectRatio(contentMode: scaleMode == "fit" ? .fit : .fill)
            }
        }
        return view
    }
}
