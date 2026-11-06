// Add-ons/ActionUIHostSurface/Tests/HostSurfaceSinkTests.swift
//
// The frame sink on Apple platforms ("kind": "sink"): announced as AUIHostSurfaceFrameSink with no handle, frames
// presented from any thread shown as the sink layer's contents (a BGRA IOSurface tagged sRGB), the newest winning,
// the shown surface never written, presents refused outside the surface's life and for frames that are not frames.

#if !os(Linux)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import IOSurface
import XCTest
import ActionUI
@testable import ActionUIHostSurface

@MainActor
final class HostSurfaceSinkTests: XCTestCase {
    private var window: TestWindow!
    private var windowUUID = ""

    override func setUp() async throws {
        HostSurfaceView.ignoresWindowOcclusionForTesting = true
        HostSurfaceRegistry.shared.resetForTesting()
        window = TestHost.makeWindow()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        HostSurfaceRegistry.shared.resetForTesting()
        TestHost.close(window)
        window = nil
        TestHost.pump()
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurfaceCount, 0, "no surface may outlive a test")
    }

    private func sink(_ viewID: Int = 5) -> HostSurfaceContainer {
        TestHost.makeContainer(windowUUID: windowUUID, viewID: viewID,
                               properties: HostSurfaceProperties(surfaceName: "viewport", kind: .sink))
    }

    /// Presents a frame of one color from another thread; the call must not wait for the main thread.
    nonisolated private static func present(_ surfaceID: UInt64, width: UInt32 = 4, height: UInt32 = 2,
                                            format: AUIHostPixelFormat = AUIHostPixelBGRX8, byte: UInt8 = 0x80) -> Bool {
        let pixels = [UInt8](repeating: byte, count: Int(width * height * 4))
        return DispatchQueue.global().sync {
            pixels.withUnsafeBytes { buffer in
                actionUIHostSurfacePresentPixels(surfaceID, width, height, width * 4, Int32(format.rawValue),
                                                 buffer.baseAddress)
            }
        }
    }

    private func shownSurface(_ container: HostSurfaceContainer) -> IOSurface? {
        guard let contents = container.surface.sinkLayer?.contents else { return nil }
        return (contents as! IOSurface)
    }

    /// The blue, green, red and alpha bytes of one pixel of a surface.
    private func bgra(_ surface: IOSurface, x: Int = 0, y: Int = 0) -> [UInt8] {
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let pixel = surface.baseAddress + y * surface.bytesPerRow + x * 4
        return (0..<4).map { pixel.load(fromByteOffset: $0, as: UInt8.self) }
    }

    func testASinkIsAnnouncedAsAFrameSinkWithNoHandle() {
        let client = RecordingCClient()
        var delegate = client.delegate
        XCTAssertTrue(actionUIHostSurfaceSetDelegate("viewport", &delegate, client.userData))
        TestHost.place(sink(), in: window)
        XCTAssertEqual(client.events, [Int32(AUIHostSurfaceCreated.rawValue)])
        XCTAssertEqual(client.entries[0].kind, Int32(AUIHostSurfaceFrameSink.rawValue))
        XCTAssertFalse(client.entries[0].hasHandle, "a frame sink has no handle")
        XCTAssertTrue(actionUIHostSurfaceSetDelegate("viewport", nil, nil))
    }

    func testFramesFromAnotherThreadAreShownAndTheNewestWins() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = sink()
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        XCTAssertEqual(HostSurfaceRegistry.shared.liveSurface(surfaceID).map { _ in true }, true)
        XCTAssertEqual(client.kinds.first, AUIHostSurfaceFrameSink, "a Swift client sees the kind too")
        XCTAssertNil(shownSurface(container), "nothing shown before a frame")

        XCTAssertTrue(Self.present(surfaceID, width: 4, height: 2))
        XCTAssertTrue(Self.present(surfaceID, width: 6, height: 3, format: AUIHostPixelRGBA8Premultiplied))
        TestHost.pump()
        let surface = try XCTUnwrap(shownSurface(container), "the frame is shown on the next main-loop turn")
        XCTAssertEqual(surface.width, 6, "the newest frame wins")
        XCTAssertEqual(surface.height, 3)
        XCTAssertNotNil(IOSurfaceCopyValue(surface, kIOSurfaceColorSpace), "tagged sRGB, matched by the render server")

        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        XCTAssertNil(shownSurface(container), "the old client's frame goes with its surface")
        XCTAssertFalse(Self.present(surfaceID), "a destroyed surface takes no frames")
    }

    func testEachPixelFormatShowsItsColors() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = sink()
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        // One pixel with red 0x30, green 0x20, blue 0x10, in each layout; alpha 0x80 is kept for the premultiplied
        // formats and becomes 0xFF for the opaque ones.
        let cases: [(AUIHostPixelFormat, [UInt8], [UInt8])] = [
            (AUIHostPixelBGRA8Premultiplied, [0x10, 0x20, 0x30, 0xFF], [0x10, 0x20, 0x30, 0xFF]),
            (AUIHostPixelRGBA8Premultiplied, [0x30, 0x20, 0x10, 0xFF], [0x10, 0x20, 0x30, 0xFF]),
            (AUIHostPixelBGRX8, [0x10, 0x20, 0x30, 0x00], [0x10, 0x20, 0x30, 0xFF]),
            (AUIHostPixelRGBX8, [0x30, 0x20, 0x10, 0x00], [0x10, 0x20, 0x30, 0xFF]),
            (AUIHostPixelBGRA8Premultiplied, [0x10, 0x20, 0x30, 0x80], [0x10, 0x20, 0x30, 0x80]),
            (AUIHostPixelRGBA8Premultiplied, [0x30, 0x20, 0x10, 0x80], [0x10, 0x20, 0x30, 0x80]),
            (AUIHostPixelBGRX8, [0x10, 0x20, 0x30, 0x80], [0x10, 0x20, 0x30, 0xFF]),
            (AUIHostPixelRGBX8, [0x30, 0x20, 0x10, 0x80], [0x10, 0x20, 0x30, 0xFF]),
        ]
        for (format, bytes, expected) in cases {
            let shown = bytes.withUnsafeBytes { buffer in
                actionUIHostSurfacePresentPixels(surfaceID, 1, 1, 4, Int32(format.rawValue), buffer.baseAddress)
            }
            XCTAssertTrue(shown)
            TestHost.pump()
            let surface = try XCTUnwrap(shownSurface(container))
            XCTAssertEqual(bgra(surface), expected, "format \(format.rawValue), alpha \(bytes[3])")
        }
    }

    func testAPaddedStrideReadsOnlyTheRowsPixels() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = sink()
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        // 3 x 2 pixels, rows 16 bytes apart, the buffer cut right after the last row's 12 bytes.
        var bytes = [UInt8](repeating: 0xEE, count: 16 + 12)
        for x in 0..<3 {
            bytes.replaceSubrange((x * 4)..<(x * 4 + 4), with: [0x10, 0x20, 0x30, 0xFF])
            bytes.replaceSubrange((16 + x * 4)..<(16 + x * 4 + 4), with: [0x10, 0x20, 0x30, 0xFF])
        }
        let shown = bytes.withUnsafeBytes { buffer in
            actionUIHostSurfacePresentPixels(surfaceID, 3, 2, 16, Int32(AUIHostPixelBGRA8Premultiplied.rawValue),
                                             buffer.baseAddress)
        }
        XCTAssertTrue(shown)
        TestHost.pump()
        let surface = try XCTUnwrap(shownSurface(container))
        XCTAssertEqual(surface.width, 3)
        XCTAssertEqual(surface.height, 2)
        XCTAssertEqual(bgra(surface, x: 2, y: 1), [0x10, 0x20, 0x30, 0xFF], "the second row from 16 bytes in")
    }

    func testAConvertedFormatReadsAnUnalignedTightlyCutBuffer() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = sink()
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        // 3 x 2 RGBX pixels, rows 14 bytes apart (not a multiple of 4), starting 1 byte into the buffer, which ends
        // right after the last row's 12 bytes.
        var bytes = [UInt8](repeating: 0xEE, count: 1 + 14 + 12)
        for row in 0..<2 {
            for x in 0..<3 {
                let start = 1 + row * 14 + x * 4
                bytes.replaceSubrange(start..<(start + 4), with: [0x30, 0x20, UInt8(0x10 + row * 3 + x), 0x00])
            }
        }
        let shown = bytes.withUnsafeBytes { buffer in
            actionUIHostSurfacePresentPixels(surfaceID, 3, 2, 14, Int32(AUIHostPixelRGBX8.rawValue), buffer.baseAddress! + 1)
        }
        XCTAssertTrue(shown)
        TestHost.pump()
        let surface = try XCTUnwrap(shownSurface(container))
        XCTAssertEqual(bgra(surface, x: 0, y: 0), [0x10, 0x20, 0x30, 0xFF])
        XCTAssertEqual(bgra(surface, x: 2, y: 1), [0x15, 0x20, 0x30, 0xFF])
    }

    func testTheShownFrameIsNeverWritten() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = sink()
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        XCTAssertTrue(Self.present(surfaceID, format: AUIHostPixelBGRA8Premultiplied, byte: 0x11))
        TestHost.pump()
        XCTAssertTrue(Self.present(surfaceID, format: AUIHostPixelBGRA8Premultiplied, byte: 0x22))
        TestHost.pump()
        let shown = try XCTUnwrap(shownSurface(container))
        XCTAssertEqual(bgra(shown), [0x22, 0x22, 0x22, 0x22])
        // Frames presented while it is shown go to other surfaces, however many come before the main thread runs.
        for byte: UInt8 in [0x33, 0x44, 0x55, 0x66] {
            XCTAssertTrue(Self.present(surfaceID, format: AUIHostPixelBGRA8Premultiplied, byte: byte))
        }
        XCTAssertEqual(bgra(shown), [0x22, 0x22, 0x22, 0x22], "the shown frame is untouched")
        TestHost.pump()
        let newest = try XCTUnwrap(shownSurface(container))
        XCTAssertEqual(bgra(newest), [0x66, 0x66, 0x66, 0x66], "the newest frame wins")
        XCTAssertFalse(newest === shown)
    }

    func testAMetalLayerSurfaceIsNoSink() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = TestHost.makeContainer(windowUUID: windowUUID, viewID: 6,
                                               properties: HostSurfaceProperties(surfaceName: "viewport"))
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        XCTAssertNil(container.surface.sinkLayer)
        XCTAssertFalse(Self.present(surfaceID), "a Metal layer takes no presented frames")
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
            let wide = UInt32(HostSurfaceSinks.maxWidth + 1)
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, wide, 1, wide * 4, bgrx, base),
                           "wider than an IOSurface takes")
            HostSurfaceSinks.close(77)
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 2, 8, bgrx, base), "a closed slot")
        }
        TestHost.pump()
    }
}

#endif
