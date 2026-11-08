// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform+Capture.swift - draws a window to a PNG. The capture is in-process
// (NSView.cacheDisplay on the window's frame view, as ActionUIViewer's offscreen mode does): no
// Screen Recording permission, no window server composite, and it works while the screen is locked.
// The window shadow is not included.

#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import MCPStdio

/// A window placed far outside every screen. AppKit would drag a titled window back onto a
/// screen when it is ordered front; this keeps the off-screen origin.
private final class OffscreenCaptureWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

extension AppKitPlatform {
    func capture(_ windowID: String) throws -> CapturedImage {
        guard let window = windows[windowID] else { throw MCPToolError("the window has no content to capture") }
        return try image(of: window)
    }

    /// In a window off every screen, which the app does not activate. Closed again before this
    /// returns. The document was built when it loaded, so its warnings are the load's.
    func renderOffscreen(_ content: Content, size: ContentSize?, delay: Double) async throws -> (image: CapturedImage, warnings: [String]) {
        let window = OffscreenCaptureWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content.controller.view
        window.title = "Preview"
        window.isExcludedFromWindowsMenu = true
        window.setContentSize(size.map { NSSize(width: $0.width, height: $0.height) } ?? Self.clampedToScreen(content.fitting))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return (try image(of: window), [])
    }

    /// Draws the window's frame view (title bar included) into a bitmap, scales it down to
    /// `maxScreenshotPixels`, and encodes it as a PNG.
    func image(of window: NSWindow) throws -> CapturedImage {
        guard let view = window.contentView?.superview ?? window.contentView else {
            throw MCPToolError("the window has no content to capture")
        }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw MCPToolError("could not create a bitmap for the window")
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard var image = rep.cgImage else { throw MCPToolError("the window produced no image") }
        let longest = max(image.width, image.height)
        if longest > WindowHost.maxScreenshotPixels, let scaled = Self.scaled(image, by: Double(WindowHost.maxScreenshotPixels) / Double(longest)) {
            image = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw MCPToolError("could not encode the screenshot")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MCPToolError("could not encode the screenshot") }
        return CapturedImage(png: data as Data, pixelWidth: image.width, pixelHeight: image.height)
    }

    private static func scaled(_ image: CGImage, by factor: Double) -> CGImage? {
        let width = max(1, Int(Double(image.width) * factor))
        let height = max(1, Int(Double(image.height) * factor))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
#endif
