// SwiftUI rendering of LoadableView; its portable part is in Core/Elements/LoadableView.swift.

import SwiftUI
import Foundation

extension LoadableView: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in

        let props = Props(properties)
        let isContentView = false
        let viewDidLoadActionID = props.viewDidLoadActionID
        // Use model.value if set (heuristics to interpret), else fall back to the current properties
        guard let value = Self.initialValue(model) as? String, !value.isEmpty else {
            logger.log("No valid source for LoadableView, displaying error SwiftUI.Text", .warning)
            return SwiftUI.Text("No valid source provided")
        }

        // Heuristics to build the appropriate content view from a string value
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            guard let url = URL(string: value) else {
                logger.log("Invalid URL: \(value)", .warning)
                return SwiftUI.Text("Invalid URL: \(value)")
            }
            logger.log("Interpreting value as remote URL: \(value)", .debug)
            return RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
        } else {
            var fileURL: URL
            if value.lowercased().hasPrefix("file://") {
                guard let url = URL(string: value), !url.path.isEmpty else {
                    logger.log("Invalid file URL: \(value)", .warning)
                    return SwiftUI.Text("Invalid file URL: \(value)")
                }
                fileURL = url
                logger.log("Interpreting value as file URL: \(value)", .debug)
            } else if value.contains("/") {
                fileURL = URL(fileURLWithPath: value)
                logger.log("Interpreting value as filePath: \(value)", .debug)
            } else {
                let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
                let resourceName = ext.isEmpty ? value : value.replacingOccurrences(of: ".\(ext)", with: "")
                let bundleExt = ext.isEmpty ? "json" : ext
                guard let url = Bundle.main.url(forResource: resourceName, withExtension: bundleExt) ??
                                Bundle.main.url(forResource: resourceName, withExtension: bundleExt == "json" ? "plist" : "json") else {
                    logger.log("Bundle resource '\(value)' not found with .json or .plist", .warning)
                    return SwiftUI.Text("Bundle resource '\(value)' not found")
                }
                fileURL = url
                logger.log("Interpreting value as bundle name: \(value)", .debug)
            }
            return FileLoadableView(fileURL: fileURL, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
        }
    }
}
