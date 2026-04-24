// Sources/Views/VideoPlayer.swift
/*
 Sample JSON for VideoPlayer:
 {
   "type": "VideoPlayer",
   "id": 1,
   "properties": {
     "url": "https://example.com/video.mp4", // Required: URL string, displays Label with error message if invalid or missing
     "autoplay": true    // Optional: Boolean for autoplay, ignored if nil
   }
   // Note: These properties are specific to VideoPlayer. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import AVKit

struct VideoPlayer: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var valueType: Any.Type = String.self // Non-optional String for URL
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate url
        if properties["url"] != nil && !(properties["url"] is String) {
            logger.log("VideoPlayer url must be a String; ignoring", .error)
            validatedProperties["url"] = nil
        }
        
        // Validate autoplay
        if let autoplay = validatedProperties["autoplay"], !(autoplay is Bool) {
            logger.log("Invalid type for VideoPlayer autoplay: expected Bool, got \(type(of: autoplay)), ignoring", .warning)
            validatedProperties["autoplay"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if canImport(AVKit)
        // Use viewModel.value if set, otherwise use initialValue
        let urlString = Self.initialValue(model) as? String ?? ""
        if let url = URL(string: urlString) {
            let player = AVPlayer(url: url)
            let videoPlayer = AVKit.VideoPlayer(player: player)
            
            // Handle autoplay with a delayed MainActor task
            if let autoplay = properties["autoplay"] as? Bool {
                Task { @MainActor in
                    // Delay to allow view to settle
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    if autoplay {
                        player.play()
                    } else {
                        player.pause()
                    }
                }
            }
            
            return videoPlayer
        } else {
            logger.log("VideoPlayer missing or invalid URL, displaying error Label", .error)
            return SwiftUI.Label("Missing or invalid URL", systemImage: "exclamationmark.triangle")
        }
        #else
        logger.log("VideoPlayer requires AVKit, displaying error Label", .error)
        return SwiftUI.Label("VideoPlayer not supported on this platform", systemImage: "exclamationmark.triangle")
        #endif
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view // No modifications needed, as autoplay is handled in buildView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        let initialValue = model.validatedProperties["url"] as? String ?? ""
        return initialValue
    }
}
