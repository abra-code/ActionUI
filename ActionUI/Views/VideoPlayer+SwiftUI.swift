// SwiftUI rendering of VideoPlayer; its portable part is in Core/Elements/VideoPlayer.swift.

import SwiftUI
import AVKit

extension VideoPlayer: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if canImport(AVKit)
        let props = Props(properties)
        // Use viewModel.value if set, otherwise use initialValue
        let urlString = Self.initialValue(model) as? String ?? ""
        if let url = URL(string: urlString) {
            // Hoist autoplay out of the closure: [String: Any] is non-Sendable.
            let autoplay = props.autoplay
            // Construction is delegated to a dedicated SwiftUI view: AVKit's VideoPlayer initializer
            // carries main-actor-isolated default arguments that cannot be resolved from this nonisolated
            // buildView closure under Swift 6. A View struct's body is @MainActor-isolated, so the AVKit
            // view (and the player it owns) are built there instead.
            return VideoPlayerContent(url: url, autoplay: autoplay)
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
}

#if canImport(AVKit)
// SwiftUI view that constructs and owns the AVKit VideoPlayer.
//
// AVKit's VideoPlayer initializer carries main-actor-isolated default arguments that cannot be evaluated
// from the nonisolated buildView closure under Swift 6 ("default argument cannot be both main actor-isolated
// and nonisolated"). A View struct's body is @MainActor-isolated, so the AVKit view can be built here. The
// AVPlayer is held in @State so it is created once and survives re-renders rather than being rebuilt.
//
// Because @State keeps its first value, a new URL written to the element's value would otherwise rebuild
// this struct around the old player and keep playing the first file. The URL is watched instead: a new one
// pauses the player and replaces its item, so the source changes while the player itself, and the volume,
// rate and AirPlay route chosen on it, stay.
private struct VideoPlayerContent: SwiftUI.View {
    let url: URL
    let autoplay: Bool?
    @State private var player: AVPlayer

    init(url: URL, autoplay: Bool?) {
        self.url = url
        self.autoplay = autoplay
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some SwiftUI.View {
        AVKit.VideoPlayer(player: player)
            .onChange(of: url) { _, newURL in
                player.pause()
                player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
            }
            .onAppear {
                guard let autoplay else { return }
                // Delay to allow the view to settle, matching the original timing.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    if autoplay {
                        player.play()
                    } else {
                        player.pause()
                    }
                }
            }
    }
}
#endif
