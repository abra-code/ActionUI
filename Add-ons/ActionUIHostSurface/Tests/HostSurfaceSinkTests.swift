// Add-ons/ActionUIHostSurface/Tests/HostSurfaceSinkTests.swift
//
// The frame sink on Apple platforms ("kind": "sink"): announced as AUIHostSurfaceFrameSink with no handle, frames
// presented from any thread shown as the sink layer's contents, the newest winning, presents refused outside the
// surface's life and for frames that are not frames.

#if !os(Linux)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
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
                                            format: AUIHostPixelFormat = AUIHostPixelBGRX8) -> Bool {
        let pixels = [UInt8](repeating: 0x80, count: Int(width * height * 4))
        return DispatchQueue.global().sync {
            pixels.withUnsafeBytes { buffer in
                actionUIHostSurfacePresentPixels(surfaceID, width, height, width * 4, Int32(format.rawValue),
                                                 buffer.baseAddress)
            }
        }
    }

    private func shownImage(_ container: HostSurfaceContainer) -> CGImage? {
        guard let contents = container.surface.sinkLayer?.contents else { return nil }
        return (contents as! CGImage)
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
        XCTAssertNil(shownImage(container), "nothing shown before a frame")

        XCTAssertTrue(Self.present(surfaceID, width: 4, height: 2))
        XCTAssertTrue(Self.present(surfaceID, width: 6, height: 3, format: AUIHostPixelRGBA8Premultiplied))
        TestHost.pump()
        let image = try XCTUnwrap(shownImage(container), "the frame is shown on the next main-loop turn")
        XCTAssertEqual(image.width, 6, "the newest frame wins")
        XCTAssertEqual(image.height, 3)

        ActionUIHostSurface.setDelegate(nil, forSurfaceName: "viewport")
        XCTAssertNil(shownImage(container), "the old client's frame goes with its surface")
        XCTAssertFalse(Self.present(surfaceID), "a destroyed surface takes no frames")
    }

    /// Red, green, blue and alpha of the one pixel of a 1 x 1 image, drawn into a known RGBA bitmap.
    private func rgba(_ image: CGImage) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }

    func testEachPixelFormatShowsItsColors() throws {
        let client = RecordingClient()
        ActionUIHostSurface.setDelegate(client, forSurfaceName: "viewport")
        let container = sink()
        TestHost.place(container, in: window)
        let surfaceID = try XCTUnwrap(client.received.first?.surfaceID)
        // One pixel with red 0x30, green 0x20, blue 0x10 (and alpha 0xFF), in each layout.
        let cases: [(AUIHostPixelFormat, [UInt8])] = [
            (AUIHostPixelBGRA8Premultiplied, [0x10, 0x20, 0x30, 0xFF]),
            (AUIHostPixelRGBA8Premultiplied, [0x30, 0x20, 0x10, 0xFF]),
            (AUIHostPixelBGRX8, [0x10, 0x20, 0x30, 0x00]),
            (AUIHostPixelRGBX8, [0x30, 0x20, 0x10, 0x00]),
        ]
        for (format, bytes) in cases {
            let shown = bytes.withUnsafeBytes { buffer in
                actionUIHostSurfacePresentPixels(surfaceID, 1, 1, 4, Int32(format.rawValue), buffer.baseAddress)
            }
            XCTAssertTrue(shown)
            TestHost.pump()
            let image = try XCTUnwrap(shownImage(container))
            XCTAssertEqual(rgba(image), [0x30, 0x20, 0x10, 0xFF], "format \(format.rawValue)")
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
        let image = try XCTUnwrap(shownImage(container))
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.bytesPerRow, 16)
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
            HostSurfaceSinks.close(77)
            XCTAssertFalse(actionUIHostSurfacePresentPixels(77, 2, 2, 8, bgrx, base), "a closed slot")
        }
        TestHost.pump()
    }
}

#endif
