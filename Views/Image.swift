/*
 Automatic embedding in Scroller idea abandoned because it complicates applying properties to appropriate view
 e.g. which properties should be applied to the scroller and which to embedded image view
 
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
     "padding": 10.0,           // Optional: CGFloat for padding
     "font": "body",             // Optional: SwiftUI font (e.g., "title", "body"), defaults to "body"
     "foregroundColor": "blue",  // Optional: SwiftUI color (e.g., "red", "blue"), defaults to primary
     "hidden": false,           // Optional: Boolean to hide the view, defaults to false
     "disabled": false          // Optional: Boolean to disable interactions, defaults to false
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
 }
*/

import SwiftUI
import UniformTypeIdentifiers

struct Image: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["systemName", "name", "filePath", "resizable", "scaleMode", "padding", "font", "foregroundColor", "hidden", "disabled"]
        var validatedProperties = properties
        
        // Ensure at least one image source is provided
        if properties["systemName"] == nil && properties["name"] == nil && properties["filePath"] == nil {
            print("Warning: Image requires one of 'systemName', 'name', or 'filePath'; defaulting to empty image")
            validatedProperties["systemName"] = "photo"
        }
        
        // Validate resizable
        if validatedProperties["resizable"] == nil {
            validatedProperties["resizable"] = true // Default to true for fit-to-size behavior
        } else if let resizable = properties["resizable"] as? Bool {
            validatedProperties["resizable"] = resizable
        } else {
            print("Warning: Image resizable must be a boolean; defaulting to true")
            validatedProperties["resizable"] = true
        }
        
        // Validate scaleMode
        if let scaleMode = properties["scaleMode"] as? String, !["fit", "fill"].contains(scaleMode) {
            print("Warning: Image scaleMode '\(scaleMode)' invalid; defaulting to 'fit'")
            validatedProperties["scaleMode"] = "fit"
        }
        if validatedProperties["scaleMode"] == nil {
            validatedProperties["scaleMode"] = "fit" // Default to fit
        }
        
        // Validate filePath
        if let filePath = properties["filePath"] as? String {
            if let uti = UTType(filenameExtension: filePath.pathExtension), 
               !uti.conforms(to: .image) && !uti.conforms(to: .pdf) {
                print("Warning: Image filePath '\(filePath)' is not an image or PDF; ignoring")
                validatedProperties["filePath"] = nil
            }
        }
        
        // Validate foregroundColor
        if let foregroundColor = properties["foregroundColor"] as? String {
            validatedProperties["foregroundColor"] = foregroundColor
        } else if properties["foregroundColor"] != nil {
            print("Warning: Image foregroundColor must be a string; defaulting to nil")
            validatedProperties["foregroundColor"] = nil
        }
        
        // Validate disabled
        if let disabled = properties["disabled"] as? Bool {
            validatedProperties["disabled"] = disabled
        } else if properties["disabled"] != nil {
            print("Warning: Image disabled must be a boolean; defaulting to false")
            validatedProperties["disabled"] = false
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Image; ignoring")
                return false
            }
        }
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
