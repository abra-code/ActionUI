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
     "disabled": false          // Optional: Boolean to disable interactions, defaults to false
   }
   // Note: These properties are specific to Image. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
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

struct Image: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        // Ensure at least one image source is provided
        if validatedProperties["systemName"] == nil && validatedProperties["name"] == nil && validatedProperties["filePath"] == nil {
            print("Warning: Image requires one of 'systemName', 'name', or 'filePath'; defaulting to empty image")
            validatedProperties["systemName"] = "photo"
        }
        
        // Validate resizable
        if validatedProperties["resizable"] == nil {
            validatedProperties["resizable"] = true // Default to true for fit-to-size behavior
        } else if let resizable = validatedProperties["resizable"] as? Bool {
            validatedProperties["resizable"] = resizable
        } else {
            print("Warning: Image resizable must be a boolean; defaulting to true")
            validatedProperties["resizable"] = true
        }
        
        // Validate scaleMode
        if let scaleMode = validatedProperties["scaleMode"] as? String, !["fit", "fill"].contains(scaleMode) {
            print("Warning: Image scaleMode '\(scaleMode)' invalid; defaulting to 'fit'")
            validatedProperties["scaleMode"] = "fit"
        }
        if validatedProperties["scaleMode"] == nil {
            validatedProperties["scaleMode"] = "fit" // Default to fit
        }
        
        // Validate filePath
        if let filePath = validatedProperties["filePath"] as? String {
            if let uti = UTType(filenameExtension: filePath.pathExtension),
               !uti.conforms(to: .image) && !uti.conforms(to: .pdf) {
                print("Warning: Image filePath '\(filePath)' is not an image or PDF; ignoring")
                validatedProperties["filePath"] = nil
            }
        }
        
        // Validate disabled
        if let disabled = validatedProperties["disabled"] as? Bool {
            validatedProperties["disabled"] = disabled
        } else if validatedProperties["disabled"] != nil {
            print("Warning: Image disabled must be a boolean; defaulting to false")
            validatedProperties["disabled"] = false
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Image") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            
            var image: SwiftUI.Image? = nil
            if let systemName = validatedProperties["systemName"] as? String {
                image = SwiftUI.Image(systemName: systemName)
            } else if let name = validatedProperties["name"] as? String {
                image = SwiftUI.Image(name)
            } else if let filePath = validatedProperties["filePath"] as? String {
                // Assuming filePath is now handled by a helper or SwiftUI directly
                image = SwiftUI.Image(filePath) // Placeholder; adjust if a helper is used
            }
            
            // Fallback to photo if no image was set
            let finalImage = image ?? SwiftUI.Image(systemName: "photo")
            
            if validatedProperties["resizable"] as? Bool ?? true {
                let scaleMode = validatedProperties["scaleMode"] as? String ?? "fit"
                image = finalImage.resizable().scaledToFit(scaleMode == "fit" ? .fit : .fill)
            } else {
                image = finalImage
            }
            
            return AnyView(image) // Base view for modifier application in ActionUIView
        }
    }
}
