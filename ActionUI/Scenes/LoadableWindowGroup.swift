// Sources/Scenes/LoadableWindowGroup.swift
/*
 Sample JSON for LoadableWindowGroup:
 {
   "type": "LoadableWindowGroup",
   "id": Int, // Optional: Non-zero positive integer
   "properties": {
     "url": String, // Optional: Remote JSON or plist URL (http://, https://)
     "filePath": String, // Optional: Absolute path to local JSON or plist
     "name": String // Optional: Name of JSON or plist resource in app bundle
   }
   // Note: Requires exactly one of "url", "filePath", or "name". Loads JSON or plist using ActionUIModel.loadSubViewDescription with isContentView: false. Remote URLs load asynchronously with ProgressView; local files load synchronously. Invalid sources or parsing errors result in a Text view. The loaded element must be a WindowGroup, or an error is displayed.
 }
*/

import SwiftUI
import Foundation

@MainActor
public struct LoadableWindowGroup : ActionUIPropertyValidation {
    static var validateProperties: ([String : Any], any ActionUILogger) -> [String : Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate property types
        if properties["url"] != nil && !(properties["url"] is String) {
            logger.log("LoadableWindowGroup url must be a String; ignoring", .warning)
            validatedProperties["url"] = nil
        }
        
        if properties["filePath"] != nil && !(properties["filePath"] is String) {
            logger.log("LoadableWindowGroup filePath must be a String; ignoring", .warning)
            validatedProperties["filePath"] = nil
        }
        
        if properties["name"] != nil && !(properties["name"] is String) {
            logger.log("LoadableWindowGroup name must be a String; ignoring", .warning)
            validatedProperties["name"] = nil
        }
        
        // Ensure exactly one source
        let sources = ["url", "filePath", "name"].compactMap { validatedProperties[$0] }
        if sources.isEmpty {
            logger.log("LoadableWindowGroup requires one of 'url', 'filePath', or 'name'; displaying error", .error)
        } else if sources.count > 1 {
            logger.log("LoadableWindowGroup has multiple sources; prioritizing 'url' > 'filePath' > 'name'", .warning)
            if validatedProperties["url"] != nil {
                validatedProperties["filePath"] = nil
                validatedProperties["name"] = nil
            } else if validatedProperties["filePath"] != nil {
                validatedProperties["name"] = nil
            }
        }
        
        return validatedProperties
    }
    
    public static func load(
        fromResource resourceName: String,
        windowUUID: String,
        logger: any ActionUILogger
    ) -> some SwiftUI.Scene {
        
        var windowGroup: SwiftUI.WindowGroup<AnyView>
        var commands: [any ActionUIElementBase] = []
        
        // Find the JSON file in the bundle
        let ext = URL(fileURLWithPath: resourceName).pathExtension.lowercased()
        let baseResourceName = ext.isEmpty ? resourceName : resourceName.replacingOccurrences(of: ".\(ext)", with: "")
        let bundleExt = ext.isEmpty ? "json" : ext
        
        if let url = Bundle.main.url(forResource: baseResourceName, withExtension: bundleExt) ??
            Bundle.main.url(forResource: baseResourceName, withExtension: bundleExt == "json" ? "plist" : "json") {
            
            do {
                // Load the JSON data and parse it into an ActionUIElement
                let data = try Data(contentsOf: url)
                let element = try ActionUIModel.shared.loadDescription(from: data, format: bundleExt, windowUUID: windowUUID)
                
                // Validate that the element is a WindowGroup
                windowGroup = WindowGroup.build(element: element, windowUUID: windowUUID, logger: logger)
                commands = element.subviews?["commands"] as? [any ActionUIElementBase] ?? []

            } catch {
                logger.log("Failed to load or parse '\(resourceName)': \(error.localizedDescription)", .error)
                windowGroup = SwiftUI.WindowGroup {
                    AnyView(SwiftUI.Text("Failed to load '\(resourceName)': \(error.localizedDescription)").foregroundStyle(.red))
                }
            }
        } else {
            logger.log("Bundle resource '\(resourceName)' not found with .json or .plist", .warning)
            windowGroup = SwiftUI.WindowGroup {
                AnyView(SwiftUI.Text("Bundle resource '\(resourceName)' not found").foregroundStyle(.red))
            }
        }
        
        return WindowGroup.applyCommands(windowGroup: windowGroup, commands: commands, windowUUID: windowUUID, logger: logger)
    }

/*
    static func buildScene(element: any ActionUIElementBase, windowUUID: String, logger: any ActionUILogger) -> some SwiftUI.Scene {
        let properties = validateProperties(element.properties, logger: logger)
        
        guard let source = (properties["url"] ?? properties["filePath"] ?? properties["name"]) as? String, !source.isEmpty else {
            logger.log("No valid source for LoadableWindowGroup id \(element.id), displaying error", .warning)
            return SwiftUI.WindowGroup {
                AnyView(SwiftUI.Text("No valid source provided").foregroundStyle(.red))
            }
        }
        
        // Heuristics to determine source type
        if source.lowercased().hasPrefix("http://") || source.lowercased().hasPrefix("https://") {
            guard let url = URL(string: source) else {
                logger.log("Invalid URL: \(source)", .warning)
                return SwiftUI.WindowGroup {
                    AnyView(SwiftUI.Text("Invalid URL: \(source)").foregroundStyle(.red))
                }
            }
            logger.log("Interpreting source as remote URL: \(source)", .debug)
            return SwiftUI.WindowGroup {
                AnyView(RemoteLoadableWindowGroupHelper(url: url, windowUUID: windowUUID, logger: logger))
            }
        } else {
            var fileURL: URL
            if source.lowercased().hasPrefix("file://") {
                guard let url = URL(string: source), !url.path.isEmpty else {
                    logger.log("Invalid file URL: \(source)", .warning)
                    return SwiftUI.WindowGroup {
                        AnyView(SwiftUI.Text("Invalid file URL: \(source)").foregroundStyle(.red))
                    }
                }
                fileURL = url
                logger.log("Interpreting source as file URL: \(source)", .debug)
            } else if source.contains("/") {
                fileURL = URL(fileURLWithPath: source)
                logger.log("Interpreting source as filePath: \(source)", .debug)
            } else {
                let ext = URL(fileURLWithPath: source).pathExtension.lowercased()
                let resourceName = ext.isEmpty ? source : source.replacingOccurrences(of: ".\(ext)", with: "")
                let bundleExt = ext.isEmpty ? "json" : ext
                guard let url = Bundle.main.url(forResource: resourceName, withExtension: bundleExt) ??
                                Bundle.main.url(forResource: resourceName, withExtension: bundleExt == "json" ? "plist" : "json") else {
                    logger.log("Bundle resource '\(source)' not found with .json or .plist", .warning)
                    return SwiftUI.WindowGroup {
                        AnyView(SwiftUI.Text("Bundle resource '\(source)' not found").foregroundStyle(.red))
                    }
                }
                fileURL = url
                logger.log("Interpreting source as bundle name: \(source)", .debug)
            }
            return SwiftUI.WindowGroup {
                AnyView(FileLoadableWindowGroupHelper(fileURL: fileURL, windowUUID: windowUUID, logger: logger))
            }
        }
    }
*/
}
