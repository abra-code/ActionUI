// Tests/Elements/VideoPlayerRendererTests.swift
/*
 Tests for the VideoPlayer renderer on GTK: no URL shows the warning Label; a URL plays in a
 GtkVideo with no size of its own that expands in both axes; autoplay plays or pauses each time the
 player is shown, and without it nothing changes; a new URL pauses and keeps the volume and mute; a
 video that cannot be played sets the stream's error. The videos play Media/one-second.mp4 (64 x 48
 H.264, written with AVAssetWriter on macOS), so they need GTK's GStreamer media backend and an
 H.264 decoder; GTK loads a video only once its player is shown, so each test shows it first.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class VideoPlayerRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var files: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "videoplayer-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for file in files {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    private func render(_ properties: String) throws -> RenderNode {
        let json = #"{"type": "VideoPlayer", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// The test video's file URL, from the package found from this file.
    private var videoURL: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Media/one-second.mp4").absoluteString
    }

    /// A copy of the test video, removed after the test.
    private func videoCopy() throws -> String {
        let path = NSTemporaryDirectory() + "actionui-video-\(ProcessInfo.processInfo.processIdentifier)-copy.mp4"
        try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.copyItem(atPath: try XCTUnwrap(URL(string: videoURL)).path, toPath: path)
        files.append(path)
        return URL(fileURLWithPath: path).absoluteString
    }

    private func video(_ node: RenderNode) throws -> WidgetPointer {
        let video = try XCTUnwrap(Gtk.Widget(node.widget).firstChild?.pointer)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(video)), "GtkVideo")
        return video
    }

    private func stream(_ video: WidgetPointer) throws -> UnsafeMutablePointer<GtkMediaStream> {
        try XCTUnwrap(gtk_video_get_media_stream(opaque(video)))
    }

    /// Shows the node's box in a window, closed after the test, and waits until it is mapped.
    private func present(_ node: RenderNode) {
        let window = gtk_window_new()!
        gtk_window_set_default_size(typed(window), 200, 150)
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        addTeardownBlock { @MainActor in
            gtk_window_set_child(typed(window), nil)
            gtk_window_destroy(typed(window))
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
    }

    /// Runs the main loop until the stream has loaded the video.
    private func waitUntilPrepared(_ stream: UnsafeMutablePointer<GtkMediaStream>, file: StaticString = #filePath, line: UInt = #line) {
        let prepared = AdwaitaTestHost.runMainLoop(until: {
            gtk_media_stream_is_prepared(stream) != 0 || gtk_media_stream_get_error(stream) != nil
        }, timeoutMilliseconds: 10_000)
        let error = gtk_media_stream_get_error(stream).flatMap { swiftString($0.pointee.message) }
        XCTAssertTrue(prepared && error == nil, "\(swiftString(G_OBJECT_TYPE_NAME_of(typed(stream))) ?? "?") not prepared: \(error ?? "timed out")", file: file, line: line)
    }

    func testNoURLShowsTheWarningLabel() throws {
        let node = try render(#""url": """#)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "GtkBox")
        let label = try XCTUnwrap(Gtk.Widget(node.widget).lastChild?.pointer)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(label))), "Missing or invalid URL")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: videoURL)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "ActionUIContainer", "a URL set later shows the player")
    }

    func testAURLPlaysInAGreedyVideoWithNoSizeOfItsOwn() throws {
        let node = try render(#""url": "\#(videoURL)""#)
        let video = try video(node)
        let file = try XCTUnwrap(gtk_video_get_file(opaque(video)))
        XCTAssertEqual(swiftString(g_file_get_uri(file)), videoURL)
        for orientation in [GTK_ORIENTATION_HORIZONTAL, GTK_ORIENTATION_VERTICAL] {
            let size = Gtk.Widget(node.widget).measure(orientation, forSize: -1)
            XCTAssertEqual(size.minimum, 0)
            XCTAssertEqual(size.natural, 0, "AVKit's VideoPlayer has no ideal size")
            XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, orientation), 0)
        }
        // GTK loads a video once its GtkVideo is shown (measured with GtkVideo alone).
        present(node)
        let stream = try stream(video)
        waitUntilPrepared(stream)
        XCTAssertEqual(gtk_media_stream_get_playing(stream), 0, "no autoplay: paused")
        XCTAssertEqual(gtk_widget_get_width(video), gtk_widget_get_width(node.widget), "the video fills the player")
        XCTAssertEqual(gtk_widget_get_height(video), gtk_widget_get_height(node.widget))
    }

    /// Hides the window showing `node` and shows it again, as SwiftUI's onAppear runs again.
    private func showAgain(_ node: RenderNode) {
        let window: WidgetPointer? = gtk_widget_get_root(node.outerWidget).map { typed($0) }
        guard let window else { return XCTFail("not in a window") }
        gtk_widget_set_visible(window, 0)
        XCTAssertEqual(gtk_widget_get_mapped(node.widget), 0)
        gtk_widget_set_visible(window, 1)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
    }

    func testAutoplayPlaysOrPausesEachTimeThePlayerIsShown() throws {
        let playing = try render(#""url": "\#(videoURL)", "autoplay": true"#)
        present(playing)
        let playingStream = try stream(try video(playing))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_media_stream_get_playing(playingStream) != 0 }), "autoplay true plays when shown")
        waitUntilPrepared(playingStream)
        gtk_media_stream_pause(playingStream)
        showAgain(playing)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_media_stream_get_playing(playingStream) != 0 }), "and again when shown again")
        ActionUIModel.shared.windowModels[windowUUID] = nil

        let paused = try render(#""url": "\#(videoURL)", "autoplay": false"#)
        present(paused)
        let pausedStream = try stream(try video(paused))
        waitUntilPrepared(pausedStream)
        gtk_media_stream_set_loop(pausedStream, 1)
        gtk_media_stream_play(pausedStream)
        showAgain(paused)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_media_stream_get_playing(pausedStream) == 0 }), "autoplay false pauses when shown")
    }

    func testWithoutAutoplayShowingChangesNothing() throws {
        let node = try render(#""url": "\#(videoURL)""#)
        present(node)
        let stream = try stream(try video(node))
        waitUntilPrepared(stream)
        gtk_media_stream_set_loop(stream, 1)
        gtk_media_stream_play(stream)
        showAgain(node)
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 300)
        XCTAssertNotEqual(gtk_media_stream_get_playing(stream), 0, "still playing after it was shown again")
    }

    func testANewURLPausesAndKeepsTheVolumeAndMute() throws {
        let node = try render(#""url": "\#(videoURL)""#)
        present(node)
        let video = try video(node)
        let first = try stream(video)
        waitUntilPrepared(first)
        gtk_media_stream_set_volume(first, 0.25)
        gtk_media_stream_set_loop(first, 1)
        gtk_media_stream_play(first)

        let copy = try videoCopy()
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: copy)
        AdwaitaTestHost.drainMainLoop()
        let second = try stream(video)
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(swiftString(g_file_get_uri(gtk_video_get_file(opaque(video)))), copy)
        waitUntilPrepared(second)
        XCTAssertEqual(gtk_media_stream_get_playing(second), 0, "a new URL does not play")
        XCTAssertEqual(gtk_media_stream_get_volume(second), 0.25, accuracy: 0.001)
        XCTAssertEqual(gtk_media_stream_get_muted(second), 0)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: copy)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try stream(video), second, "the same URL again leaves the video as it is")

        // Muted, GTK reports the volume as 0; the one set before carries on.
        gtk_media_stream_set_muted(second, 1)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: videoURL)
        AdwaitaTestHost.drainMainLoop()
        let third = try stream(video)
        waitUntilPrepared(third)
        XCTAssertNotEqual(gtk_media_stream_get_muted(third), 0)
    }

    /// GStreamer's criticals while `run` runs: GTK's GStreamer stream has no player before its
    /// file opens, and a volume or mute set then is a critical and never reaches the player.
    private func playerCriticals(during run: () -> Void) -> Int {
        let count = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        count.pointee = 0
        defer { count.deallocate() }
        let handler = g_log_set_handler("GStreamer-Player", G_LOG_LEVEL_CRITICAL, { _, _, _, data in
            data?.assumingMemoryBound(to: Int.self).pointee += 1
        }, count)
        run()
        g_log_remove_handler("GStreamer-Player", handler)
        return count.pointee
    }

    func testANewURLWhileThePlayerIsOutOfItsWindowKeepsTheVolumeAndMuteOnceShown() throws {
        let node = try render(#""url": "\#(videoURL)""#)
        present(node)
        let video = try video(node)
        let window = try XCTUnwrap(gtk_widget_get_root(node.outerWidget))
        /// Takes the player out of its window (the video is unrealized: a new stream does not open
        /// its file), shows `url`, puts the player back and returns the new stream once prepared.
        func showOutOfTheWindow(_ url: String) throws -> UnsafeMutablePointer<GtkMediaStream> {
            let criticals = playerCriticals {
                gtk_window_set_child(typed(window), nil)
                XCTAssertEqual(gtk_widget_get_realized(video), 0)
                ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: url)
                AdwaitaTestHost.drainMainLoop()
            }
            XCTAssertEqual(criticals, 0, "no volume or mute set before the stream opens its file")
            gtk_window_set_child(typed(window), node.outerWidget)
            let stream = try stream(video)
            waitUntilPrepared(stream)
            return stream
        }
        let first = try stream(video)
        waitUntilPrepared(first)
        gtk_media_stream_set_volume(first, 0.25)
        let second = try showOutOfTheWindow(videoURL + "?second")
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(gtk_media_stream_get_volume(second), 0.25, accuracy: 0.001)
        XCTAssertEqual(gtk_media_stream_get_muted(second), 0)

        gtk_media_stream_set_muted(second, 1)
        let third = try showOutOfTheWindow(videoURL + "?third")
        XCTAssertNotEqual(gtk_media_stream_get_muted(third), 0)
    }

    func testAVideoThatCannotPlaySetsTheError() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory() + "actionui-video-missing.mp4").absoluteString
        let node = try render(#""url": "\#(missing)""#)
        present(node)
        let stream = try stream(try video(node))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_media_stream_get_error(stream) != nil }, timeoutMilliseconds: 10_000))
    }
}
