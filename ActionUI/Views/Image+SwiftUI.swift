// SwiftUI rendering of Image; its portable part is in Core/Elements/Image.swift.

import SwiftUI
import UniformTypeIdentifiers

extension Image: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        var image: SwiftUI.Image

        // Runtime value (set via set_string / set_value) takes precedence
        // over static properties.  Interpreted using "mixed" heuristics.
        if let runtimeValue = model.value as? String, !runtimeValue.isEmpty {
            image = SwiftUI.Image(from: runtimeValue, interpretation: "mixed")
        } else {
            // The first source that can be shown. A filePath whose extension is a known
            // non-image type is skipped.
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
