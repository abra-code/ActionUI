// Sources/Elements/VideoPlayer+WinUI.swift
/*
 VideoPlayer on WinUI: WinUI's MediaPlayerElement, the video with Windows' transport controls over
 it, as AVKit's player shows its own. Windows plays it through Media Foundation, with the codecs the
 system has. It follows ActionUI's Apple backing (Views/VideoPlayer+SwiftUI.swift) and the Linux
 renderer (VideoPlayer+Adwaita.swift):
 - The URL is the value, else the url property (VideoPlayer.initialValue). One that is no URL shows
   a Label "Missing or invalid URL" with a warning icon instead, logged as an error.
 - Greedy in both axes with no size of its own, as AVKit's VideoPlayer is (a FillLayout with an
   ideal of 0); the video is fitted inside, keeping its aspect ratio.
 - autoplay: each time the player is shown (SwiftUI's onAppear; WinUI's Loaded), a tenth of a second
   later, true plays and false pauses; without it, nothing (the player starts paused).
 - A new URL pauses the player and shows the new video, keeping the volume and mute chosen, as the
   Apple backing keeps its AVPlayer; it does not start playing.
 - When the video has opened, that is logged (with its size); a video that cannot be played shows
   the controls' own error and the reason is logged (a file not found, a format without a codec, a
   network error, a URL that is not absolute).
 - A file: address that names something other than a regular file (a device, a named pipe) is not
   opened, and that is logged as an error: the document names the address.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI
import Dispatch

/// What a VideoPlayer shows, kept in its node's state.
@MainActor final class VideoPlayerState {
    let stack: ZStackLayout
    /// The player (a MediaPlayerElement) in its layout, made for the first URL and kept.
    var player: WinUIObject?
    var fill: FillLayout?
    /// The Label shown for no URL, made when first needed.
    var label: IconTitleLayout?
    /// The URL shown, so an update showing it again leaves the video as it is.
    var url: String?
    /// The player's status as last logged ("opened ...", "failed: ...").
    var shownStatus = "none"

    init(stack: ZStackLayout) {
        self.stack = stack
    }
}

extension VideoPlayer: ActionUIWinUIRenderer {
    static let invalidURLText = "Missing or invalid URL"

    /// Both axes for a player; the Label for no URL keeps its size.
    static func expansion(_ node: RenderNode) -> Expansion {
        url(node) != nil ? .both : []
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let stack = try ZStackLayout()
        node.state = VideoPlayerState(stack: stack)
        return stack.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? VideoPlayerState else { return }
        guard let url = url(node) else {
            showLabel(node, state)
            return
        }
        guard let player = player(node, state), let fill = state.fill else {
            showLabel(node, state)
            return
        }
        state.stack.setItems([ZStackLayout.Item(view: fill.panel.object, expansion: .both)])
        if url.absoluteString != state.url {
            state.url = url.absoluteString
            show(url, in: player, node, state)
        }
    }

    /// The URL to play, nil when the value is none.
    private static func url(_ node: RenderNode) -> URL? {
        URL(string: initialValue(node.model) as? String ?? "")
    }

    /// The player, made (with its handlers) the first time a URL is shown; nil (logged) when WinUI
    /// could not make it.
    private static func player(_ node: RenderNode, _ state: VideoPlayerState) -> WinUIObject? {
        if let player = state.player { return player }
        let logger = ActionUIModel.shared.logger
        guard let player = WinUIObject(adopting: actionUIWinUIVideoPlayerCreate()) else {
            logger.log("VideoPlayer: \(WinUIError.last("making the player"))", .error)
            return nil
        }
        let fill: FillLayout
        do {
            fill = try FillLayout(child: player)
        } catch {
            logger.log("VideoPlayer: \(error)", .error)
            return nil
        }
        fill.ideal = 0
        state.player = player
        state.fill = fill
        WinUIEvents.connect(player, actionUIWinUIVideoPlayerOnChanged, "a VideoPlayer's video") { [weak node, weak player] in
            guard let node, let player, node.isAttached, let state = node.state as? VideoPlayerState else { return }
            logStatus(player, node, state)
        }
        // SwiftUI's onAppear: on every showing.
        WinUIEvents.connect(player, actionUIWinUIElementOnLoaded, "a VideoPlayer's showing") { [weak node, weak player] in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak node, weak player] in
                MainActor.assumeIsolated {
                    guard let node, let player, node.isAttached, let autoplay = Props(node.properties).autoplay else { return }
                    if !actionUIWinUIVideoPlayerSetPlaying(player.pointer, autoplay) {
                        logger.log("VideoPlayer: \(WinUIError.last(autoplay ? "playing" : "pausing"))", .error)
                    }
                }
            }
        }
        return player
    }

    /// Replaces the video the player shows with the one at `url`, paused.
    private static func show(_ url: URL, in player: WinUIObject, _ node: RenderNode, _ state: VideoPlayerState) {
        let logger = ActionUIModel.shared.logger
        state.shownStatus = "none"
        // A document names the address: a file: one must be a regular file, not a device or a named
        // pipe. A missing file goes on to the player, which reports it.
        if url.isFileURL, FileManager.default.fileExists(atPath: url.path),
           ActionUIDocumentLoader.regularFilePath(url) == nil {
            logger.log("VideoPlayer not playing '\(url.absoluteString)': \(url.path) is not a regular file", .error)
            if !actionUIWinUIVideoPlayerSetSource(player.pointer, nil) {
                logger.log("VideoPlayer: \(WinUIError.last("clearing the video"))", .error)
            }
            return
        }
        if !actionUIWinUIVideoPlayerSetSource(player.pointer, url.absoluteString) {
            logger.log("VideoPlayer: \(WinUIError.last("showing \(url.absoluteString)"))", .error)
            return
        }
        // A URL the player refuses at once (not absolute) reports it now.
        logStatus(player, node, state)
    }

    /// Logs the player's status when it changed: the video opened, or why it cannot be played.
    private static func logStatus(_ player: WinUIObject, _ node: RenderNode, _ state: VideoPlayerState) {
        guard let copy = actionUIWinUIVideoPlayerCopyStatus(player.pointer) else { return }
        let status = String(cString: copy)
        actionUIWinUIFreeString(copy)
        guard status != state.shownStatus else { return }
        state.shownStatus = status
        let url = state.url ?? ""
        let logger = ActionUIModel.shared.logger
        if status.hasPrefix("failed: ") {
            logger.log("VideoPlayer \(node.element.id) could not play '\(url)': \(status.dropFirst("failed: ".count))", .error)
        } else if status.hasPrefix("opened ") {
            logger.log("VideoPlayer \(node.element.id) opened '\(url)' (video \(status.dropFirst("opened ".count)))", .info)
        }
    }

    /// The Label for no URL, as Label(systemImage:) shows it, in the player's place (paused and
    /// emptied when there is one).
    private static func showLabel(_ node: RenderNode, _ state: VideoPlayerState) {
        // First, so a Label that cannot be made does not leave the video playing out of view.
        if state.url != nil, let player = state.player {
            state.url = nil
            state.shownStatus = "none"
            if !actionUIWinUIVideoPlayerSetSource(player.pointer, nil) {
                ActionUIModel.shared.logger.log("VideoPlayer: \(WinUIError.last("clearing the video"))", .error)
            }
        }
        if state.label == nil {
            ActionUIModel.shared.logger.log("VideoPlayer missing or invalid URL, displaying error Label", .error)
            do {
                let label = try IconTitleLayout()
                label.setTitle(invalidURLText)
                label.setIcon(ImageLayout.makeSymbol("exclamationmark.triangle"))
                state.label = label
            } catch {
                ActionUIModel.shared.logger.log("VideoPlayer: \(error)", .error)
                state.stack.setItems([])
                return
            }
        }
        guard let label = state.label else { return }
        node.applyTextAppearance(to: label.title, what: "a VideoPlayer's Label")
        if let icon = label.icon {
            Paint.apply(Paint.parse(node.textAppearance.foreground, role: .foreground), ActionUIWinUIBrushForeground,
                        to: icon, what: "a VideoPlayer's Label symbol")
        }
        label.setIconSide(ImageLayout.symbolSide(node, scale: nil))
        state.stack.setItems([ZStackLayout.Item(view: label.panel.object)])
    }
}
