// Sources/Views/Image.swift
/*
 Sample JSON for Image:
 {
   "type": "Image",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "systemName": "star.fill",  // Optional: String for SF Symbol
     "assetName": "customImage",      // Optional: String for asset catalog image name
     "filePath": "/path/to/image.jpg", // Optional: String for local file path
     "resourceName": "yourImage.png",  Optional: String for bundle resource image name with extension
     "resizable": true,          // Optional: Boolean to make image resizable, defaults to true if contentMode is specified
     "contentMode": "fit",       // Optional: String ("fit" or "fill") for aspect-ratio scaling mode, defaults to "fit"
     "imageScale": "large"       // Optional: String ("small", "medium", "large") for image scale, applies to SF Symbols, no default
   }
   // Note: These properties are specific to Image. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled, accessibilityLabel, accessibilityHint, accessibilityHidden, accessibilityIdentifier, shadow) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
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

extension Image {
    /// Image's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// One image source and its name or path.
        enum Source: Equatable, Sendable {
            case filePath(String)
            case resourceName(String)
            case assetName(String)
            case systemName(String)
        }

        enum ContentMode: String, Sendable, CaseIterable {
            case fit, fill
        }

        enum ImageScale: String, Sendable, CaseIterable {
            case small, medium, large
        }

        /// Every source given as a String, most specific first: filePath, resourceName, assetName,
        /// systemName. The renderer uses the first one it can show (a filePath that is not an
        /// image or PDF is skipped there).
        var sources: [Source] = []
        /// "contentMode", else the deprecated alias "scaleMode"; nil when neither is "fit" or "fill".
        var contentMode: ContentMode?
        /// "resizable" when it is a Bool, else true exactly when a content mode is set.
        var resizable = false
        var imageScale: ImageScale?

        init(_ properties: [String: Any]) {
            if let filePath = properties["filePath"] as? String { sources.append(.filePath(filePath)) }
            if let resourceName = properties["resourceName"] as? String { sources.append(.resourceName(resourceName)) }
            if let assetName = properties["assetName"] as? String { sources.append(.assetName(assetName)) }
            if let systemName = properties["systemName"] as? String { sources.append(.systemName(systemName)) }
            contentMode = (properties["contentMode"] as? String).flatMap(ContentMode.init(rawValue:))
                ?? (properties["scaleMode"] as? String).flatMap(ContentMode.init(rawValue:))
            resizable = properties["resizable"] as? Bool ?? (contentMode != nil)
            imageScale = (properties["imageScale"] as? String).flatMap(ImageScale.init(rawValue:))
        }
    }
}

struct Image: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // The runtime value of an Image is a string interpreted using "mixed" heuristics
    // (file path, SF Symbol name, or asset name).  Setting the value programmatically
    // overrides the static source properties (systemName, assetName, filePath, resourceName).
    static var valueType: Any.Type = String?.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate systemName
        if properties["systemName"] != nil && !(properties["systemName"] is String) {
            logger.log("Image systemName must be a String; ignoring", .warning)
            validatedProperties["systemName"] = nil
        }
        
        // Validate name
        if properties["assetName"] != nil && !(properties["assetName"] is String) {
            logger.log("Image assetName must be a String; ignoring", .warning)
            validatedProperties["assetName"] = nil
        }

        // Validate resourceName
        if properties["resourceName"] != nil && !(properties["resourceName"] is String) {
            logger.log("Image resourceName must be a String; ignoring", .warning)
            validatedProperties["resourceName"] = nil
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
        
        // Validate contentMode (preferred); scaleMode is a deprecated alias
        if let contentMode = properties["contentMode"] as? String {
            if !["fit", "fill"].contains(contentMode) {
                logger.log("Image contentMode '\(contentMode)' invalid; ignoring", .warning)
                validatedProperties["contentMode"] = nil
            }
        } else if properties["contentMode"] != nil {
            logger.log("Image contentMode must be a String; ignoring", .warning)
            validatedProperties["contentMode"] = nil
        }
        if let scaleMode = properties["scaleMode"] as? String {
            if !["fit", "fill"].contains(scaleMode) {
                logger.log("Image scaleMode '\(scaleMode)' invalid; ignoring", .warning)
                validatedProperties["scaleMode"] = nil
            } else if validatedProperties["contentMode"] is String {
                logger.log("Image: both contentMode and scaleMode set; using contentMode, cleared scaleMode", .info)
                validatedProperties["scaleMode"] = nil
            } else {
                logger.log("Image scaleMode is deprecated; use contentMode instead", .info)
            }
        } else if properties["scaleMode"] != nil {
            logger.log("Image scaleMode must be a String; ignoring", .warning)
            validatedProperties["scaleMode"] = nil
        }
        
        // Validate imageScale
        if let imageScale = properties["imageScale"] as? String {
            if !["small", "medium", "large"].contains(imageScale) {
                logger.log("Image imageScale '\(imageScale)' invalid; ignoring", .warning)
                validatedProperties["imageScale"] = nil
            }
        } else if properties["imageScale"] != nil {
            logger.log("Image imageScale must be a String; ignoring", .warning)
            validatedProperties["imageScale"] = nil
        }
        
        // Enforce mutual exclusivity among image source properties.
        // When multiple are present (e.g. runtime set_property added "filePath"
        // while "systemName" remains from the original JSON), keep only the
        // most specific one.  Priority: filePath > resourceName > assetName > systemName.
        let sourceKeys = ["filePath", "resourceName", "assetName", "systemName"]
        let presentSources = sourceKeys.filter { validatedProperties[$0] is String }
        if presentSources.count > 1, let winner = presentSources.first {
            for key in presentSources.dropFirst() {
                validatedProperties[key] = nil
            }
            logger.log("Image: multiple source properties set; using '\(winner)', cleared \(presentSources.dropFirst().joined(separator: ", "))", .info)
        }

        // Check if all image source properties are nil
        if presentSources.isEmpty {
            logger.log("Image requires one of 'systemName', 'assetName', 'resourceName' or 'filePath'; defaulting to empty image", .warning)
        }

        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        var image: SwiftUI.Image

        // Runtime value (set via set_string / set_value) takes precedence
        // over static properties.  Interpreted using "mixed" heuristics.
        if let runtimeValue = model.value as? String, !runtimeValue.isEmpty {
            image = SwiftUI.Image(from: runtimeValue, interpretation: "mixed")
        } else {
            // The first source that can be shown. A filePath whose extension is a known
            // non-image type is skipped, as validation dropped it.
            let source = props.sources.first { source in
                if case .filePath(let filePath) = source {
                    let pathExtension = URL(fileURLWithPath: filePath).pathExtension
                    if let uti = UTType(filenameExtension: pathExtension),
                       !uti.conforms(to: .image) && !uti.conforms(to: .pdf) {
                        return false
                    }
                }
                return true
            }
            switch source {
            case .filePath(let filePath)?:
                image = SwiftUI.Image(from: filePath, interpretation: "path")
            case .resourceName(let resourceName)?:
                image = SwiftUI.Image(from: resourceName, interpretation: "resourceName")
            case .assetName(let name)?:
                image = SwiftUI.Image(name)
            case .systemName(let systemName)?:
                image = SwiftUI.Image(systemName: systemName)
            case nil:
                image = SwiftUI.Image(systemName: "photo")
            }
        }

        // contentMode implies "resizable" even if not explicitly declared (see Props)
        if props.resizable, let contentMode = props.contentMode {
            switch contentMode {
            case .fit: return image.resizable().aspectRatio(contentMode: .fit)
            case .fill: return image.resizable().aspectRatio(contentMode: .fill)
            }
        }

        return image
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        // Returns non-nil only when a runtime value was explicitly set
        // via set_string / set_value.  Nil means "use static properties"
        // — buildView handles those with their specific interpretations.
        return model.value as? String
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        
        var modifiedView = view
        
        // Apply imageScale modifier
        if let imageScale = Props(properties).imageScale {
            switch imageScale {
            case .small: modifiedView = view.imageScale(.small)
            case .medium: modifiedView = view.imageScale(.medium)
            case .large: modifiedView = view.imageScale(.large)
            }
        }
                
        return modifiedView
    }
}
