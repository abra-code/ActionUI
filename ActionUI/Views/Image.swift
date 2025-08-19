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
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["systemName"] == nil && validatedProperties["name"] == nil && validatedProperties["filePath"] == nil {
            logger.log("Image requires one of 'systemName', 'name', or 'filePath'; defaulting to empty image", .warning)
            validatedProperties["systemName"] = "photo"
        }
        
        if validatedProperties["resizable"] == nil {
            validatedProperties["resizable"] = true
        } else if let resizable = validatedProperties["resizable"] as? Bool {
            validatedProperties["resizable"] = resizable
        } else {
            logger.log("Image resizable must be a boolean; defaulting to true", .warning)
            validatedProperties["resizable"] = true
        }
        
        if let scaleMode = validatedProperties["scaleMode"] as? String, !["fit", "fill"].contains(scaleMode) {
            logger.log("Image scaleMode '\(scaleMode)' invalid; defaulting to 'fit'", .warning)
            validatedProperties["scaleMode"] = "fit"
        }
        if validatedProperties["scaleMode"] == nil {
            validatedProperties["scaleMode"] = "fit"
        }
        
        if let filePath = validatedProperties["filePath"] as? String {
            let pathExtension = URL(fileURLWithPath: filePath).pathExtension
            if let uti = UTType(filenameExtension: pathExtension),
               !uti.conforms(to: .image) && !uti.conforms(to: .pdf) {
                logger.log("Image filePath '\(filePath)' is not an image or PDF; ignoring", .warning)
                validatedProperties["filePath"] = nil
            }
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        var image: SwiftUI.Image
        if let systemName = properties["systemName"] as? String {
            image = SwiftUI.Image(systemName: systemName)
        } else if let name = properties["name"] as? String {
            image = SwiftUI.Image(name)
        } else if let filePath = properties["filePath"] as? String {
            image = SwiftUI.Image(from: filePath, interpretation: "path")
        } else {
            image = SwiftUI.Image(systemName: "photo")
        }
        
        return image
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        if let resizable = properties["resizable"] as? Bool, resizable {
            let scaleMode = (properties["scaleMode"] as? String) ?? "fit"
            if let imageView = view as? SwiftUI.Image {
                return imageView.resizable().aspectRatio(contentMode: scaleMode == "fit" ? .fit : .fill)
            }
        }
        return view
    }
}
