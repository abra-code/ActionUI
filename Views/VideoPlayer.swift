/*
 Sample JSON for VideoPlayer:
 {
   "type": "VideoPlayer",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/video.mp4", // Optional: URL string for video, defaults to nil
     "autoplay": true    // Optional: Boolean for autoplay, defaults to false
   }
   // Note: These properties are specific to VideoPlayer. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import AVKit

struct VideoPlayer: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let urlString = validatedProperties["url"] as? String {
            if let url = URL(string: urlString) {
                validatedProperties["url"] = url
            } else {
                print("Warning: VideoPlayer url '\(urlString)' invalid; defaulting to nil")
                validatedProperties["url"] = nil
            }
        }
        if validatedProperties["autoplay"] == nil {
            validatedProperties["autoplay"] = false
        } else if let autoplay = validatedProperties["autoplay"] as? Bool {
            validatedProperties["autoplay"] = autoplay
        } else {
            print("Warning: VideoPlayer autoplay must be a Boolean; defaulting to false")
            validatedProperties["autoplay"] = false
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if canImport(AVKit)
        registry.register("VideoPlayer") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            guard let url = properties["url"] as? URL else {
                print("Warning: VideoPlayer requires a valid URL")
                return AnyView(EmptyView())
            }
            let player = AVPlayer(url: url)
            let autoplay = properties["autoplay"] as? Bool ?? false
            if autoplay {
                player.play()
            }
            return AnyView(
                VideoPlayer(player: player)
            )
        }
        #else
        registry.register("VideoPlayer") { _, _, _ in
            print("Warning: VideoPlayer requires AVKit")
            return AnyView(EmptyView())
        }
        #endif
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        #if canImport(AVKit)
        registry.register("autoplay") { view, properties in
            guard let autoplay = properties["autoplay"] as? Bool else { return view }
            if let player = (view as? VideoPlayerRepresentable)?.player {
                if autoplay {
                    player.play()
                } else {
                    player.pause()
                }
            }
            return view
        }
        #endif
    }
}
