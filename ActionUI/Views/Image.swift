// Sources/Views/Image.swift
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
        
        // Validate systemName
        if properties["systemName"] != nil && !(properties["systemName"] is String) {
            logger.log("Image systemName must be a String; ignoring", .warning)
            validatedProperties["systemName"] = nil
        }
        
        // Validate name
        if properties["name"] != nil && !(properties["name"] is String) {
            logger.log("Image name must be a String; ignoring", .warning)
            validatedProperties["name"] = nil
        }
        
        // Validate filePath
        if let filePath = properties["filePath"] as? String {
            let pathExtension = URL(fileURLWithPath: filePath).pathExtension
            if let uti = UTType(filenameExtension: pathExtension),
               !uti.conforms(to: .image) && !uti.conforms(to: .pdf) {
                logger.log("Image filePath '\(filePath)' is not an image or PDF; ignoring", .warning)
                validatedProperties["filePath"] = nil
            }
        } else if properties["filePath"] != nil {
            logger.log("Image filePath must be a String; ignoring", .warning)
            validatedProperties["filePath"] = nil
        }
        
        // Validate resizable
        if properties["resizable"] != nil && !(properties["resizable"] is Bool) {
            logger.log("Image resizable must be a Bool; ignoring", .warning)
            validatedProperties["resizable"] = nil
        }
        
        // Validate scaleMode
        if let scaleMode = properties["scaleMode"] as? String {
            if !["fit", "fill"].contains(scaleMode) {
                logger.log("Image scaleMode '\(scaleMode)' invalid; ignoring", .warning)
                validatedProperties["scaleMode"] = nil
            }
        } else if properties["scaleMode"] != nil {
            logger.log("Image scaleMode must be a String; ignoring", .warning)
            validatedProperties["scaleMode"] = nil
        }
        
        // Check if all image source properties are nil
        if validatedProperties["systemName"] == nil && validatedProperties["name"] == nil && validatedProperties["filePath"] == nil {
            logger.log("Image requires one of 'systemName', 'name', or 'filePath'; defaulting to empty image", .warning)
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
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
        let resizable = properties["resizable"] as? Bool ?? true
        if resizable {
            let scaleMode = (properties["scaleMode"] as? String) ?? "fit"
            if let imageView = view as? SwiftUI.Image {
                return imageView.resizable().aspectRatio(contentMode: scaleMode == "fit" ? .fit : .fill)
            }
        }
        return view
    }
}
