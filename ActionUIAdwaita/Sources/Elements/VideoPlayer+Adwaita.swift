// Sources/Elements/VideoPlayer+Adwaita.swift
/*
 VideoPlayer on GTK: a GtkVideo, the video with GTK's playback controls over it, as AVKit's player
 shows its own. GTK plays it through GStreamer: built into GTK 4.20 and later, a GTK module before
 that (Debian 13's package libgtk-4-media-gstreamer, which its GNOME desktop installs).
 It follows ActionUI's Apple backing (Views/VideoPlayer+SwiftUI.swift):
 - The URL is the value, else the url property (VideoPlayer.initialValue). One that is no URL shows
   a Label "Missing or invalid URL" with a warning icon instead, logged as an error.
 - Greedy in both axes with no size of its own, as AVKit's VideoPlayer is (measured on macOS 27: it
   takes a 500 x 400 window's whole width beside a Text and its whole height beside one, and
   fixedSize makes it 0 x 0); the video is fitted inside, keeping its aspect ratio.
 - autoplay: each time the player is shown (SwiftUI's onAppear), a tenth of a second later, true
   plays and false pauses; without it, nothing (the player starts paused).
 - GTK loads the video once the player is first shown (measured with a GtkVideo alone).
 - A new URL pauses the player and shows the new video, keeping the volume and mute chosen, as the
   Apple backing keeps its AVPlayer; it does not start playing. GTK reports a muted video's volume
   as 0 (and keeps 0 after unmuting), so the volume carried is the last one set while not muted.
 - A video that cannot be played shows GTK's error icon, the reason in its tooltip, and the reason
   is logged (a missing GStreamer plug-in or media module, a file not found, a network error).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

nonisolated(unsafe) private var videoLayoutType: GType = 0
private let videoStateKey = AttachKey<VideoPlayerState>("actionui-video-player")

/// What a VideoPlayer's handlers share, kept on its container.
@MainActor private final class VideoPlayerState {
    weak var node: RenderNode?
    /// The URL shown, so an update showing it again leaves the video as it is.
    var url: String?
    /// The volume last set while not muted: GTK reports a muted stream's volume as 0.
    var volume = 1.0
    /// Whether the video is muted, carried to a new URL's video with the volume.
    var muted: gboolean = 0
}

extension VideoPlayer: ActionUIAdwaitaRenderer {
    enum Kind: Int {
        case player = 0, invalidURL
    }

    static let invalidURLText = "Missing or invalid URL"

    static func widgetKind(_ node: RenderNode) -> Int {
        (url(node) != nil ? Kind.player : Kind.invalidURL).rawValue
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        guard Kind(rawValue: node.widgetKind) == .player else {
            // As Label(systemImage:) shows it.
            let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, Label.iconSpacing)!
            let icon = newWidget(gtk_image_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
            gtk_image_set_from_icon_name(opaque(icon), Image.iconName(.symbol("exclamationmark.triangle")))
            gtk_box_append(typed(box), icon)
            gtk_box_append(typed(box), gtk_label_new(invalidURLText))
            return box
        }
        let container = makeContainer(layoutType: layoutType())
        let video = gtk_video_new()!
        gtk_widget_set_parent(video, container)
        gtk_widget_set_hexpand(container, 1)
        gtk_widget_set_vexpand(container, 1)
        let state = VideoPlayerState()
        state.node = node
        attach(state, to: container, key: videoStateKey)
        // SwiftUI's onAppear: on every showing.
        connectSignal(video, "map", .instanceOnly) { [weak state] in
            runAfter(milliseconds: 100) { [weak state] in
                guard let node = state?.node, let autoplay = Props(node.properties).autoplay,
                      gtk_widget_get_mapped(video) != 0, let stream = gtk_video_get_media_stream(opaque(video)) else { return }
                if autoplay {
                    gtk_media_stream_play(stream)
                } else {
                    gtk_media_stream_pause(stream)
                }
            }
        }
        return container
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: videoStateKey), let video = layoutChildren(widget).first else { return }
        guard let url = url(node), url.absoluteString != state.url else { return }
        state.url = url.absoluteString
        show(url, in: video, state)
    }

    static var defaultExpansion: Expansion { .both }

    /// The URL to play, nil (logged) when the value is none.
    private static func url(_ node: RenderNode) -> URL? {
        guard let url = URL(string: initialValue(node.model) as? String ?? "") else {
            ActionUIModel.shared.logger.log("VideoPlayer missing or invalid URL, displaying error Label", .error)
            return nil
        }
        return url
    }

    /// Replaces the video `video` plays with the one at `url`, paused, with the old one's volume
    /// and mute.
    private static func show(_ url: URL, in video: WidgetPointer, _ state: VideoPlayerState) {
        if let previous = gtk_video_get_media_stream(opaque(video)) {
            gtk_media_stream_pause(previous)
        }
        let file = g_file_new_for_uri(url.absoluteString)
        gtk_video_set_file(opaque(video), file)
        g_object_unref(UnsafeMutableRawPointer(file))
        guard let stream = gtk_video_get_media_stream(opaque(video)) else { return }
        // GTK's GStreamer stream makes its player when it opens its file, which the video gives it
        // once realized; a volume or mute set before that never reaches the player (and GStreamer
        // logs a critical for each), so they are set once the file is open ("file" is notified
        // after the opening).
        let volume = state.volume
        let muted = state.muted
        let carry: @MainActor () -> Void = {
            guard gtk_media_file_get_file(typed(stream)) != nil else { return }
            gtk_media_stream_set_volume(stream, volume)
            gtk_media_stream_set_muted(stream, muted)
        }
        if gtk_media_file_get_file(typed(stream)) != nil {
            carry()
        } else {
            connectSignal(UnsafeMutableRawPointer(stream), "notify::file", .instanceAndArgument, carry)
        }
        connectSignal(UnsafeMutableRawPointer(stream), "notify::volume", .instanceAndArgument) { [weak state] in
            if gtk_media_stream_get_muted(stream) == 0 {
                state?.volume = gtk_media_stream_get_volume(stream)
            }
        }
        connectSignal(UnsafeMutableRawPointer(stream), "notify::muted", .instanceAndArgument) { [weak state] in
            state?.muted = gtk_media_stream_get_muted(stream)
        }
        let urlString = url.absoluteString
        let logError: @MainActor () -> Void = {
            guard let error = gtk_media_stream_get_error(stream) else { return }
            let message = swiftString(error.pointee.message) ?? "unknown error"
            ActionUIModel.shared.logger.log("VideoPlayer could not play '\(urlString)': \(message)", .error)
        }
        // GTK sets some errors (no media module) as it makes the stream, the others later.
        logError()
        connectSignal(UnsafeMutableRawPointer(stream), "notify::error", .instanceAndArgument, logError)
    }

    // MARK: Layout

    /// A layout giving the video any size from 0, naturally 0, and all of the container's size.
    static func layoutType() -> GType {
        if videoLayoutType != 0 { return videoLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            // Always 0, whatever the other axis: no height-for-width measuring of the video.
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_CONSTANT_SIZE }
            layoutClass.pointee.measure = { _, _, _, _, minimum, natural, minimumBaseline, naturalBaseline in
                minimum?.pointee = 0
                natural?.pointee = 0
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated {
                    for child in layoutChildren(widget) {
                        gtk_widget_allocate(child, width, height, -1, nil)
                    }
                }
            }
        }
        videoLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIVideoLayout", &info, GTypeFlags(0))
        return videoLayoutType
    }
}
