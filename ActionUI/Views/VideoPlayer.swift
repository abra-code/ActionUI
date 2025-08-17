// Sources/Views/VideoPlayer.swift
/*
 Sample JSON for VideoPlayer:
 {
   "type": "VideoPlayer",
   "id": 1,
   "properties": {
     "url": "https://example.com/video.mp4", // Optional: URL string, returns EmptyView if nil or invalid
     "autoplay": true    // Optional: Boolean for autoplay, ignored if nil
   }
   // Note: These properties are specific to VideoPlayer. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import AVKit

struct VideoPlayer: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let urlString = validatedProperties["url"] as? String {
            if URL(string: urlString) == nil {
                logger.log("Invalid VideoPlayer url '\(urlString)', ignoring", .warning)
                validatedProperties["url"] = nil
            }
        } else if validatedProperties["url"] != nil {
            logger.log("Invalid type for VideoPlayer url: expected String, got \(type(of: properties["url"]!)), ignoring", .warning)
            validatedProperties["url"] = nil
        }
        
        if let autoplay = validatedProperties["autoplay"], !(autoplay is Bool) {
            logger.log("Invalid type for VideoPlayer autoplay: expected Bool, got \(type(of: autoplay)), ignoring", .warning)
            validatedProperties["autoplay"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        #if canImport(AVKit)
        guard let url = properties["url"] as? URL else {
            logger.log("VideoPlayer missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let player = AVPlayer(url: url)
        return AVKit.VideoPlayer(player: player)
        #else
        logger.log("VideoPlayer requires AVKit, returning EmptyView", .warning)
        return SwiftUI.EmptyView()
        #endif
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        #if canImport(AVKit)
        var modifiedView = view
        if let autoplay = properties["autoplay"] as? Bool, let player = (modifiedView as? any VideoPlayerRepresentable)?.player {
            if autoplay {
                player.play()
            } else {
                player.pause()
            }
        }
        return modifiedView
        #else
        return view
        #endif
    }
}

// Placeholder protocol for VideoPlayerRepresentable (to be refined with actual player access)
protocol VideoPlayerRepresentable: SwiftUI.View {
    var player: AVPlayer? { get }
}
