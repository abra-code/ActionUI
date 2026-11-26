// Core/Elements/Image.swift
/*
 Sample JSON for Image:
 {
   "type": "Image",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "systemName": "star.fill",  // Optional: String for SF Symbol
     "assetName": "customImage",      // Optional: String for asset catalog image name
     "filePath": "/path/to/image.jpg", // Optional: String, absolute local file path (a relative one resolves against the process's working directory)
     "resourceName": "yourImage.png",  // Optional: String for a resource image name with extension (the host's resource folder, then the bundle; a name with "/" is not found)
     "resizable": true,          // Optional: Boolean, defaults to false. true scales the image to the space it is given (its frame); with no contentMode it stretches to fill it on both axes, not keeping its aspect ratio, as SwiftUI's .resizable() does. false: the image keeps its own size and a smaller frame does not shrink it
     "contentMode": "fit",       // Optional: String ("fit" or "fill"), no default. Keeps a resizable image's aspect ratio: "fit" shows the whole image inside the frame, "fill" covers the frame and may draw past it. No effect unless "resizable" is true, as SwiftUI's .aspectRatio(contentMode:) has none on an image that is not resizable
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
        /// "contentMode"; nil when it is not "fit" or "fill".
        var contentMode: ContentMode?
        /// "resizable" when it is a Bool, else false. A content mode does not imply it, as in
        /// SwiftUI, where .aspectRatio(contentMode:) does not scale an image that is not resizable.
        var resizable = false
        var imageScale: ImageScale?

        init(_ properties: [String: Any]) {
            if let filePath = properties["filePath"] as? String { sources.append(.filePath(filePath)) }
            if let resourceName = properties["resourceName"] as? String { sources.append(.resourceName(resourceName)) }
            if let assetName = properties["assetName"] as? String { sources.append(.assetName(assetName)) }
            if let systemName = properties["systemName"] as? String { sources.append(.systemName(systemName)) }
            contentMode = (properties["contentMode"] as? String).flatMap(ContentMode.init(rawValue:))
            resizable = properties["resizable"] as? Bool ?? false
            imageScale = (properties["imageScale"] as? String).flatMap(ImageScale.init(rawValue:))
        }
    }
}

struct Image: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // The runtime value of an Image is a string interpreted using "mixed" heuristics
    // (file path, SF Symbol name, or asset name).  Setting the value programmatically
    // overrides the static source properties (systemName, assetName, filePath, resourceName).
    static var valueType: Any.Type = String?.self

    static var initialValue: (ViewModel) -> Any? = { model in
        // Returns non-nil only when a runtime value was explicitly set
        // via set_string / set_value.  Nil means "use static properties"
        // — buildView handles those with their specific interpretations.
        return model.value as? String
    }
}
