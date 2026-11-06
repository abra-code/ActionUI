// Add-ons/ActionUIHostSurface/Tests/HostSurfaceGtkTests.swift
//
// The element on Linux, in a real application window: the surface events (created at the frame's size, hidden
// at load, hidden and resized later without a destroy, a replaced client told first, window close), frames asked
// for and continuous, frames presented from another thread, the size state, and the placeholder for a kind Linux
// lacks, and dmabuf frames (when /dev/udmabuf is available). An application runs once in a process, so this is one
// scripted test whose steps run on the application's main loop. The binding rules are shared with the Apple element
// and tested there too.

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
    private(set) var renders = 0
    /// Events and input kinds in the order they came.
    private(set) var log: [String] = []
    /// Runs inside the surface callback, before the event is recorded.
    var onEvent: ((HostSurfaceEvent) -> Void)?

    func hostSurface(_ surface: HostSurfaceInfo, event: HostSurfaceEvent) {
        onEvent?(event)
        events.append(event)
        infos.append(surface)
        log.append("\(event)")
    }

    func hostSurfaceRender(_ surface: HostSurfaceInfo) {
        renders += 1
    }

    func hostSurfaceInput(_ surface: HostSurfaceInfo, event: HostSurfaceInput) {
        log.append("input \(event.kind.rawValue)")
    }

    func hostSurfaceFrame(_ surface: HostSurfaceInfo, timestamp: Double) {
        frames += 1
    }

    var surfaceID: UInt64 { infos.last?.surfaceID ?? 0 }
}

/// What the C client of "gl-c" saw: its events and renders (callbacks run on the main thread).
nonisolated(unsafe) private var cEvents: [Int32] = []
nonisolated(unsafe) private var cRenders = 0
nonisolated(unsafe) private var cKind: Int32 = 0

/// The tags of the dmabuf frames handed back, in order, and whether every release ran on the main thread.
nonisolated(unsafe) private var dmabufReleased: [Int] = []
nonisolated(unsafe) private var dmabufReleasedOffMain = false
private let recordRelease: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
    if g_main_context_is_owner(g_main_context_default()) == 0 {
        dmabufReleasedOffMain = true
    }
    dmabufReleased.append(Int(bitPattern: data))
}

/// A C delegate, as a C or Rust client binds one, for the render callback's C path.
nonisolated(unsafe) private var cDelegate = AUIHostSurfaceDelegate(
    structSize: UInt32(MemoryLayout<AUIHostSurfaceDelegate>.size),
    surface: { _, _, _, event, info, _ in
        cEvents.append(event)
        if let info {
            cKind = info.pointee.kind
        }
    },
    frame: nil,
    input: nil,
    render: { _, _, _, _ in cRenders += 1 })

@MainActor
final class HostSurfaceGtkTests: XCTestCase {
    private let windowUUID = "host-surface-gtk"
    private var stepsRun = 0

    private let document = """
        {"type": "VStack", "properties": {"frame": {"width": 400}}, "children": [
            {"type": "HostSurface", "id": 5, "properties": {"surfaceName": "viewport", "frame": {"width": 200, "height": 120}}},
            {"type": "HostSurface", "id": 6, "properties": {"surfaceName": "other", "idealWidth": 50, "idealHeight": 40,
                                                            "hidden": true}},
            {"type": "HostSurface", "id": 7, "properties": {"surfaceName": "placeholder", "kind": "vulkan"}},
            {"type": "HostSurface", "id": 8, "properties": {"surfaceName": "gl", "kind": "gl", "frame": {"width": 100, "height": 80}}},
            {"type": "HostSurface", "id": 9, "properties": {"surfaceName": "gl-c", "kind": "gl", "frame": {"width": 60, "height": 40}}}
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

    /// The shown texture is a GdkDmabufTexture.
    private func showsDmabuf(_ surfaceID: UInt64) -> Bool {
        guard let texture = HostSurfaceRegistry.shared.liveSurface(surfaceID)?.texture else { return false }
        return g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(texture), gdk_dmabuf_texture_get_type()) != 0
    }

    /// The first pixel of the shown texture, downloaded as GDK's default format (blue, green, red, alpha).
    private func firstPixel(_ surfaceID: UInt64) -> [UInt8] {
        guard let texture = HostSurfaceRegistry.shared.liveSurface(surfaceID)?.texture else { return [] }
        let width = Int(gdk_texture_get_width(texture))
        let height = Int(gdk_texture_get_height(texture))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            gdk_texture_download(texture, buffer.baseAddress?.assumingMemoryBound(to: guchar.self), gsize(width * 4))
        }
        return Array(pixels.prefix(4))
    }

    private func presentDmabuf(_ surfaceID: UInt64, _ buffer: AUIHostDmabuf) -> Bool {
        var copy = buffer
        return actionUIHostSurfacePresentDmabuf(surfaceID, &copy)
    }

    /// The buffers presented by the dmabuf steps, alive until the test ends.
    private var dmabufs: [TestDmabuf] = []

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
        let gl = RecordingClient()
        let glSuccessor = RecordingClient()
        ActionUIHostSurface.setDelegate(gl, forSurfaceName: "gl")
        XCTAssertTrue(actionUIHostSurfaceSetDelegate("gl-c", &cDelegate, nil), "a C client binds on the main thread")
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
                XCTAssertEqual(gl.events, [.created], "the GL area is announced once it has a context")
                XCTAssertEqual(gl.infos.first?.widthPoints, 100)
                XCTAssertNotNil(HostSurfaceRegistry.shared.liveSurface(gl.surfaceID)?.glArea, "a GtkGLArea child")
                XCTAssertFalse(presentFromAnotherThread(gl.surfaceID), "a GL area is no frame sink")
                ActionUIHostSurface.requestFrame(surfaceID: gl.surfaceID)
                XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 4, "the placeholder announces nothing")
                XCTAssertEqual(cEvents, [Int32(AUIHostSurfaceCreated.rawValue)], "the C client got created")
                XCTAssertEqual(cKind, Int32(AUIHostSurfaceGLArea.rawValue), "for a GL area")
                firstID = first.surfaceID
                XCTAssertTrue(presentFromAnotherThread(firstID), "a live surface takes a frame from any thread")
                XCTAssertFalse(presentFromAnotherThread(9_999), "an unknown surface does not")
                ActionUIHostSurface.requestFrame(surfaceID: firstID)
            },
            { [self] in
                XCTAssertEqual(textureWidth(firstID), 4, "the presented frame is shown")
                XCTAssertGreaterThanOrEqual(gl.frames, 1, "the GL client got its frame")
                XCTAssertGreaterThanOrEqual(gl.renders, 1, "and the render it asked for")
                XCTAssertGreaterThanOrEqual(cRenders, 1, "the C client's render callback is called (the area's first show)")
                XCTAssertEqual(first.frames, 1, "one requested frame came, and no more")

                // dmabuf frames: the formats, the argument checks, and a frame dropped before it was shown.
                let count = actionUIHostSurfaceCopyDmabufFormats(firstID, nil, 0)
                XCTAssertGreaterThan(count, 0, "the display imports dmabufs")
                var formats = [AUIHostDmabufFormat](repeating: AUIHostDmabufFormat(), count: Int(count))
                XCTAssertEqual(actionUIHostSurfaceCopyDmabufFormats(firstID, &formats, count), count)
                XCTAssertTrue(formats.contains { $0.fourcc == testDrmFormatARGB8888 && $0.modifier == 0 },
                              "ARGB8888 in the linear layout")
                XCTAssertEqual(actionUIHostSurfaceCopyDmabufFormats(gl.surfaceID, nil, 0), 0, "a GL area is no frame sink")
                guard let a = TestDmabuf(width: 8, height: 4, pixel: [0x10, 0x20, 0x30, 0xFF]),
                      let b = TestDmabuf(width: 6, height: 2, pixel: [0x40, 0x40, 0x40, 0xFF]),
                      let c = TestDmabuf(width: 5, height: 3, pixel: [0x30, 0x20, 0x10, 0xFF]) else {
                    print("HOSTSURFACE dmabuf steps skipped: /dev/udmabuf is not available")
                    return
                }
                dmabufs = [a, b, c]
                let tag = { (number: Int) in UnsafeMutableRawPointer(bitPattern: number) }
                var bad = a.frame(release: recordRelease, releaseData: tag(9), fourcc: 0x2020_2020)
                XCTAssertFalse(presentDmabuf(firstID, bad), "a format the display does not import")
                bad = a.frame(release: recordRelease, releaseData: tag(9))
                bad.planeCount = 0
                XCTAssertFalse(presentDmabuf(firstID, bad), "no planes")
                bad = a.frame(release: nil, releaseData: nil)
                XCTAssertFalse(presentDmabuf(firstID, bad), "no release callback")
                bad = a.frame(release: recordRelease, releaseData: tag(9))
                bad.structSize -= 8
                XCTAssertFalse(presentDmabuf(firstID, bad), "another struct size")
                bad.structSize += 8
                bad.planes.0.fd = -1
                XCTAssertFalse(presentDmabuf(firstID, bad), "a plane with no fd")
                XCTAssertFalse(presentDmabuf(gl.surfaceID, a.frame(release: recordRelease, releaseData: tag(9))),
                               "a GL area takes no dmabuf")
                XCTAssertFalse(actionUIHostSurfacePresentDmabuf(firstID, nil))
                let frameA = a.frame(release: recordRelease, releaseData: tag(1))
                let frameB = b.frame(release: recordRelease, releaseData: tag(2))
                let presented = DispatchQueue.global().sync { [self] in
                    (presentDmabuf(firstID, frameB), presentDmabuf(firstID, frameA))
                }
                XCTAssertTrue(presented.0 && presented.1, "a dmabuf frame from any thread")
            },
            { [self] in
                guard dmabufs.count == 3 else {
                    setProperty(5, "hidden", true)
                    return
                }
                XCTAssertTrue(showsDmabuf(firstID), "a GdkDmabufTexture")
                XCTAssertEqual(textureWidth(firstID), 8, "the newest frame wins")
                XCTAssertEqual(firstPixel(firstID), [0x10, 0x20, 0x30, 0xFF], "GTK reads the client's buffer")
                XCTAssertEqual(dmabufReleased, [2], "the frame dropped before it was shown is handed back, and no other")
                XCTAssertFalse(dmabufReleased.contains(9), "a refused frame is never handed back")
                XCTAssertTrue(presentDmabuf(firstID, dmabufs[2].frame(release: recordRelease, releaseData: UnsafeMutableRawPointer(bitPattern: 3))))
            },
            { [self] in
                if dmabufs.count == 3 {
                    XCTAssertEqual(textureWidth(firstID), 5, "the next dmabuf frame is shown")
                    XCTAssertEqual(firstPixel(firstID), [0x30, 0x20, 0x10, 0xFF])
                }
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
                // Keyboard focus: the surface is focusable with a client, and tells it.
                XCTAssertNotEqual(view.map { gtk_widget_get_focusable($0.widget) }, 0, "focusable with a client")
                view.map { _ = gtk_widget_grab_focus($0.widget) }
                // A window opened by a test is not activated by the compositor, so keys would not come: FocusIn waits
                // for an active window, as on Apple platforms for the key window.
                let windowActive = view.flatMap { gtk_widget_get_root($0.widget) }.map {
                    gtk_window_is_active(UnsafeMutableRawPointer($0).assumingMemoryBound(to: GtkWindow.self)) != 0
                } ?? false
                XCTAssertEqual(view.map { gtk_widget_is_focus($0.widget) }, 1, "the surface takes the window's focus")
                let focusIn = "input \(AUIHostInputFocusIn.rawValue)"
                if windowActive {
                    XCTAssertEqual(first.log.last, focusIn, "FocusIn when it takes focus")
                } else {
                    XCTAssertFalse(first.log.contains(focusIn), "no FocusIn while the window is not active")
                }
                ActionUIHostSurface.setDelegate(replacement, forSurfaceName: "viewport")
                XCTAssertEqual(first.events.last, .destroyed, "the outgoing client is told first")
                if windowActive {
                    XCTAssertEqual(Array(first.log.suffix(2)), ["input \(AUIHostInputFocusOut.rawValue)", "destroyed"],
                                   "FocusOut before destroyed")
                }
                XCTAssertEqual(view.map { gtk_widget_is_focus($0.widget) }, 0, "the focus is given up")
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
                // A client rebinding inside the GL area's "destroyed": the area is not announced again for the
                // context that is about to go.
                gl.onEvent = { event in
                    if event == .destroyed {
                        ActionUIHostSurface.setDelegate(glSuccessor, forSurfaceName: "gl")
                    }
                }
                AdwaitaApplication.shared.closeWindow(windowUUID)
            },
            { [self] in
                XCTAssertEqual(replacement.events.last, .destroyed, "closing the window destroys")
                XCTAssertEqual(second.events.last, .destroyed)
                XCTAssertEqual(gl.events.last, .destroyed, "the GL area's surface goes with its window")
                XCTAssertEqual(cEvents.last, Int32(AUIHostSurfaceDestroyed.rawValue), "and the C client's")
                XCTAssertEqual(glSuccessor.events, [], "no created for a context about to go")
                XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0)
                XCTAssertFalse(presentFromAnotherThread(replacement.surfaceID))
            },
            { [self] in
                // A shown dmabuf is handed back once GTK lets go of its texture: replaced, or its surface destroyed.
                if dmabufs.count == 3 {
                    XCTAssertEqual(dmabufReleased.sorted(), [1, 2, 3], "every presented dmabuf handed back once")
                    XCTAssertFalse(dmabufReleasedOffMain, "and on the main thread")
                }
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

    func testInputTables() {
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 30 + 8), "KeyA")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 44 + 8), "KeyZ")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 16 + 8), "KeyQ")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 2 + 8), "Digit1")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 11 + 8), "Digit0")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 59 + 8), "F1")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 68 + 8), "F10")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 88 + 8), "F12")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 105 + 8), "ArrowLeft")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 125 + 8), "MetaLeft")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 3), "", "below the evdev offset")
        XCTAssertEqual(HostSurfaceGtkInput.code(hardwareKeycode: 500), "")

        XCTAssertEqual(HostSurfaceGtkInput.button(1), 0)
        XCTAssertEqual(HostSurfaceGtkInput.button(3), 1, "the right button is the secondary")
        XCTAssertEqual(HostSurfaceGtkInput.button(2), 2, "the middle button")
        let state = GDK_SHIFT_MASK.rawValue | GDK_SUPER_MASK.rawValue | GDK_LOCK_MASK.rawValue
        XCTAssertEqual(HostSurfaceGtkInput.modifiers(state),
                       UInt32(AUIHostModifierShift | AUIHostModifierMeta | AUIHostModifierCapsLock))
        XCTAssertTrue(HostSurfaceGtkInput.buttonHeld(GDK_BUTTON1_MASK.rawValue))
        XCTAssertFalse(HostSurfaceGtkInput.buttonHeld(GDK_SHIFT_MASK.rawValue))
        XCTAssertEqual(HostSurfaceGtkInput.heldButton(GDK_BUTTON3_MASK.rawValue), 1, "a right drag is the secondary")
        XCTAssertEqual(HostSurfaceGtkInput.heldButton(GDK_BUTTON2_MASK.rawValue), 2)
        XCTAssertEqual(HostSurfaceGtkInput.heldButton(GDK_BUTTON1_MASK.rawValue | GDK_BUTTON3_MASK.rawValue), 0)

        // GDK's deltas say how far the view scrolls; the header's how far the content moves.
        XCTAssertTrue(HostSurfaceGtkInput.contentDelta(0, 3) == (0, -3))
        XCTAssertTrue(HostSurfaceGtkInput.stepDelta(GDK_SCROLL_UP)! == (0, 1), "the wheel up moves the content down")
        XCTAssertTrue(HostSurfaceGtkInput.stepDelta(GDK_SCROLL_RIGHT)! == (-1, 0))

        XCTAssertEqual(HostSurfaceGtkInput.text(unicode: 0x61, state: 0), "a")
        XCTAssertEqual(HostSurfaceGtkInput.text(unicode: 0x1F600, state: GDK_SHIFT_MASK.rawValue), "\u{1F600}")
        XCTAssertNil(HostSurfaceGtkInput.text(unicode: 0x61, state: GDK_CONTROL_MASK.rawValue), "a shortcut, not text")
        XCTAssertNil(HostSurfaceGtkInput.text(unicode: 0x1B, state: 0), "Escape")
        XCTAssertNil(HostSurfaceGtkInput.text(unicode: 0, state: 0))

        var clicks = HostSurfaceClickCounter()
        XCTAssertEqual(clicks.press(button: 0, x: 10, y: 10, timeMilliseconds: 1000, doubleClickTime: 400, doubleClickDistance: 5), 1)
        XCTAssertEqual(clicks.press(button: 0, x: 12, y: 11, timeMilliseconds: 1300, doubleClickTime: 400, doubleClickDistance: 5), 2)
        XCTAssertEqual(clicks.press(button: 0, x: 12, y: 11, timeMilliseconds: 1600, doubleClickTime: 400, doubleClickDistance: 5), 3)
        XCTAssertEqual(clicks.press(button: 0, x: 40, y: 11, timeMilliseconds: 1700, doubleClickTime: 400, doubleClickDistance: 5), 1, "too far")
        XCTAssertEqual(clicks.press(button: 1, x: 40, y: 11, timeMilliseconds: 1800, doubleClickTime: 400, doubleClickDistance: 5), 1, "another button")
        XCTAssertEqual(clicks.press(button: 1, x: 40, y: 11, timeMilliseconds: 2300, doubleClickTime: 400, doubleClickDistance: 5), 1, "too late")
        XCTAssertEqual(clicks.press(button: 1, x: 40, y: 11, timeMilliseconds: 2, doubleClickTime: 400, doubleClickDistance: 5), 1,
                       "an earlier time is not a double click")
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
