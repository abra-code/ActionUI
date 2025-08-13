/*
 Sample JSON for VideoPlayer:
 {
   "type": "VideoPlayer",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/video.mp4", // Optional: URL string for video, defaults to nil
     "autoplay": true    // Optional: Boolean for autoplay, defaults to false
   }
   // Note: These properties are specific to VideoPlayer. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import AVKit

struct VideoPlayer: ActionUIViewConstruction {
    // Design decision: Defines valueType as Void since VideoPlayer manages AVPlayer without user-modifiable state
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
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
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        #if canImport(AVKit)
        guard let url = properties["url"] as? URL else {
            print("Warning: VideoPlayer requires a valid URL")
            return SwiftUI.EmptyView()
        }
        let player = AVPlayer(url: url)
        return AVKit.VideoPlayer(player: player)
        #else
        print("Warning: VideoPlayer requires AVKit")
        return SwiftUI.EmptyView()
        #endif
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> AnyView = { view, properties in
        #if canImport(AVKit)
        var modifiedView = view
        if let autoplay = properties["autoplay"] as? Bool, let player = (modifiedView as? any VideoPlayerRepresentable)?.player {
            if autoplay {
                player.play()
            } else {
                player.pause()
            }
        }
        return AnyView(modifiedView)
        #else
        return view
        #endif
    }
}

// Placeholder protocol for VideoPlayerRepresentable (to be refined with actual player access)
protocol VideoPlayerRepresentable: SwiftUI.View {
    var player: AVPlayer? { get }
}
