// Add-ons/ActionUIHostSurface/Tests/HostSurfaceGtkTests.swift
//
// The element on Linux, in a real application window: the surface events (created at the frame's size, hidden
// at load, hidden and resized later without a destroy, a replaced client told first, window close), frames asked
// for and continuous, frames presented from another thread, the size state, and the placeholder for a kind Linux
// lacks. An application runs once in a process, so this is one scripted test whose steps run on the application's
// main loop. The binding rules are shared with the Apple element and tested there too.

#if os(Linux)

import XCTest
import ActionUI
import CAdwaita
import Dispatch
import FoundationEssentials
@testable import ActionUIHostSurface

/// A logger that keeps what it is handed, so a test can assert a warning fired.
final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var entries: [(String, LoggerLevel)] = []

    func log(_ message: String, _ level: LoggerLevel) {
        entries.append((message, level))
    }

    var warnings: [String] {
        entries.filter { $0.1 == .warning }.map(\.0)
    }
}

/// A Swift client that records its events and frames, and can run code inside a callback.
@MainActor
private final class RecordingClient: HostSurfaceDelegate {
    private(set) var events: [HostSurfaceEvent] = []
    private(set) var infos: [HostSurfaceInfo] = []
    private(set) var frames = 0

    func hostSurface(_ surface: HostSurfaceInfo, event: HostSurfaceEvent) {
        events.append(event)
        infos.append(surface)
    }

    func hostSurfaceFrame(_ surface: HostSurfaceInfo, timestamp: Double) {
        frames += 1
    }

    var surfaceID: UInt64 { infos.last?.surfaceID ?? 0 }
}

@MainActor
final class HostSurfaceGtkTests: XCTestCase {
    private let windowUUID = "host-surface-gtk"
    private var stepsRun = 0

    private let document = """
        {"type": "VStack", "properties": {"frame": {"width": 400}}, "children": [
            {"type": "HostSurface", "id": 5, "properties": {"surfaceName": "viewport", "frame": {"width": 200, "height": 120}}},
            {"type": "HostSurface", "id": 6, "properties": {"surfaceName": "other", "idealWidth": 50, "idealHeight": 40,
                                                            "hidden": true}},
            {"type": "HostSurface", "id": 7, "properties": {"surfaceName": "placeholder", "kind": "gl"}}
        ]}
        """

    private func setProperty(_ id: Int, _ name: String, _ value: Any) {
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: id, propertyName: name, value: value)
    }

    /// Presents a small frame for a surface from another thread; the call must not wait for the main thread,
    /// which waits here.
    private func presentFromAnotherThread(_ surfaceID: UInt64, width: UInt32 = 4, height: UInt32 = 2) -> Bool {
        let pixels = [UInt8](repeating: 0x80, count: Int(width * height * 4))
        return DispatchQueue.global().sync {
            pixels.withUnsafeBytes { buffer in
                actionUIHostSurfacePresentPixels(surfaceID, width, height, width * 4,
                                                 Int32(AUIHostPixelBGRX8.rawValue), buffer.baseAddress)
            }
        }
    }

    private func textureWidth(_ surfaceID: UInt64) -> Int32? {
        guard let texture = HostSurfaceRegistry.shared.liveSurface(surfaceID)?.texture else { return nil }
        return gdk_texture_get_width(texture)
    }

    func testTheElementInAWindow() throws {
        try XCTSkipUnless(gtk_init_check() != 0, "needs a display")
        // The C entry point, on the thread the application runs on: it holds on the main actor there too.
        ActionUIHostSurface_register()
        HostSurfaceRegistry.shared.resetForTesting()

        let first = RecordingClient()
        let second = RecordingClient()
        let replacement = RecordingClient()
        ActionUIHostSurface.setDelegate(first, forSurfaceName: "viewport")
        ActionUIHostSurface.setDelegate(second, forSurfaceName: "other")
        var firstID: UInt64 = 0

        // Each step runs after the updates of the one before it, on the main loop.
        let steps: [() -> Void] = [
            { [self] in
                XCTAssertEqual(first.events, [.created], "a client bound before the window opened is told once it has a size")
                let info = first.infos[0]
                XCTAssertEqual(info.widthPoints, 200)
                XCTAssertEqual(info.heightPoints, 120)
                XCTAssertGreaterThan(info.scale, 0)
                XCTAssertEqual(info.widthPixels, Int((200 * info.scale).rounded()))
                XCTAssertEqual(second.events, [.created, .suspended], "hidden at load: created, then suspended")
                XCTAssertEqual(second.infos.first?.widthPoints, 400, "it grows to the width it is offered")
                XCTAssertEqual(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 5, key: "size") as? [Double],
                               [200, 120], "the size state")
                XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 2, "the placeholder announces nothing")
                firstID = first.surfaceID
                XCTAssertTrue(presentFromAnotherThread(firstID), "a live surface takes a frame from any thread")
                XCTAssertFalse(presentFromAnotherThread(9_999), "an unknown surface does not")
                ActionUIHostSurface.requestFrame(surfaceID: firstID)
            },
            { [self] in
                XCTAssertEqual(textureWidth(firstID), 4, "the presented frame is shown")
                XCTAssertEqual(first.frames, 1, "one requested frame came, and no more")
                setProperty(5, "hidden", true)
            },
            { [self] in
                XCTAssertEqual(first.events, [.created, .suspended], "hidden suspends")
                setProperty(5, "hidden", false)
                setProperty(5, "frame", ["width": 300, "height": 120])
            },
            { [self] in
                XCTAssertEqual(first.events, [.created, .suspended, .resumed, .changed],
                               "shown again and resized, with the same surface")
                XCTAssertEqual(first.infos.last?.widthPoints, 300)
                XCTAssertEqual(first.infos.map(\.surfaceID), Array(repeating: firstID, count: 4))
                XCTAssertEqual(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 5, key: "size") as? [Double],
                               [300, 120])
                let view = HostSurfaceRegistry.shared.liveSurface(firstID)
                XCTAssertTrue(ActionUIHostSurface.setCursor(Int32(AUIHostCursorHidden.rawValue), surfaceID: firstID))
                XCTAssertNotNil(view.flatMap { gtk_widget_get_cursor($0.widget) })
                ActionUIHostSurface.setDelegate(replacement, forSurfaceName: "viewport")
                XCTAssertEqual(first.events.last, .destroyed, "the outgoing client is told first")
                XCTAssertEqual(view?.cursor, Int32(AUIHostCursorArrow.rawValue), "the old client's cursor ends at destroyed")
                XCTAssertNil(view.flatMap { gtk_widget_get_cursor($0.widget) })
                XCTAssertEqual(replacement.events, [.created])
                XCTAssertNotEqual(replacement.surfaceID, firstID, "a new surfaceID with every created")
                XCTAssertNil(textureWidth(replacement.surfaceID), "the old client's frame is not shown to the new one")
                XCTAssertFalse(presentFromAnotherThread(firstID), "a destroyed surface takes no frames")
                ActionUIHostSurface.setContinuous(true, surfaceID: replacement.surfaceID)
            },
            { [self] in
                XCTAssertGreaterThanOrEqual(replacement.frames, 2, "continuous frames come")
                AdwaitaApplication.shared.closeWindow(windowUUID)
            },
            { [self] in
                XCTAssertEqual(replacement.events.last, .destroyed, "closing the window destroys")
                XCTAssertEqual(second.events.last, .destroyed)
                XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
                XCTAssertFalse(presentFromAnotherThread(replacement.surfaceID))
                stepsRun += 1
            },
        ]

        let app = AdwaitaApplication.shared
        app.applicationID = "com.abracode.actionui.hostsurface.tests"
        app.handlers.windowWillPresent = { _ in
            Self.run(steps[...]) {
                app.terminate()
            }
        }
        app.presentWindow(json: Data(document.utf8), windowUUID: windowUUID, title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(stepsRun, 1, "every step ran")
        HostSurfaceRegistry.shared.resetForTesting()
    }

    func testPresentRejectsWhatIsNotAFrame() {
        let pixels = [UInt8](repeating: 0, count: 64)
        pixels.withUnsafeBytes { buffer in
            let base = buffer.baseAddress
            let bgrx = Int32(AUIHostPixelBGRX8.rawValue)
            XCTAssertFalse(actionUIHostSurfacePresentPixels(1, 2, 2, 8, bgrx, nil), "no pixels")
            XCTAssertFalse(actionUIHostSurfacePresentPixels(1, 2, 2, 8, bgrx, base), "no live surface")
            HostSurfaceSinks.open(77)
            XCTAssertTrue(actionUIHostSurfacePresentPixels(77, 2, 2, 8, bgrx, base))
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 0, 2, 8, bgrx, base), "no width")
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 0, 8, bgrx, base), "no height")
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 2, 7, bgrx, base), "a stride shorter than a row")
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 2, 8, 0, base), "an unknown format")
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 2, 8, 5, base), "an unknown format")
            // Sizes GdkMemoryTexture cannot take, and a buffer size past Int: false, not a trap.
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 1_073_741_823, 2_147_483_649, 4_294_967_295, bgrx, base),
                           "a height past Int32")
            XCTAssertFalse(ActionUIHostSurface.presentPixels(surfaceID: 77, width: Int.max / 2, height: 1, stride: Int.max,
                                                             format: bgrx, pixels: base!), "a width past Int32")
            XCTAssertFalse(ActionUIHostSurface.presentPixels(surfaceID: 77, width: 1, height: 2, stride: Int.max,
                                                             format: bgrx, pixels: base!), "stride + the last row past Int")
            HostSurfaceSinks.close(77)
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 2, 8, bgrx, base), "a closed slot")
        }
        XCTAssertEqual(HostSurfaceSinks.memoryFormat(Int32(AUIHostPixelRGBA8Premultiplied.rawValue)),
                       GDK_MEMORY_R8G8B8A8_PREMULTIPLIED)
    }

    private static func run(_ steps: ArraySlice<() -> Void>, then finish: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
            MainActor.assumeIsolated {
                guard let step = steps.first else {
                    finish()
                    return
                }
                step()
                run(steps.dropFirst(), then: finish)
            }
        }
    }
}

#endif
