// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost+Capture.swift - screenshots of an open window, or of a document rendered in a window
// that never appears on any screen. The capture is in-process (NSView.cacheDisplay on the window's
// frame view, as ActionUIViewer's offscreen mode does): no Screen Recording permission, no window
// server composite, and it works while the screen is locked. The window shadow is not included.

import AppKit
import UniformTypeIdentifiers
import MCPStdio

/// A window placed far outside every screen. AppKit would drag a titled window back onto a
/// screen when it is ordered front; this keeps the off-screen origin.
private final class OffscreenCaptureWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

struct Screenshot: Sendable {
    let png: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let path: String
}

extension WindowHost {
    /// Longest side of a returned image, in pixels. Larger captures are scaled down, which keeps
    /// the image content block small enough to be useful to a model.
    static let maxScreenshotPixels = 1600
    /// Saved screenshots kept on disk; older ones are removed, so a long session that iterates on
    /// a layout does not fill the temporary folder.
    static let keptScreenshots = 50

    /// Captures an open window after `delay` seconds (so images and web content can load).
    func captureWindow(_ windowID: String, delay: Double) async throws -> Screenshot {
        try requireWindow(windowID)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard let window = windows[windowID] else {
            throw MCPToolError("window \(windowID) was closed before it could be captured")
        }
        return try screenshot(of: window, name: "window")
    }

    /// Renders `document` in a window off every screen, captures it after `delay` seconds, and
    /// closes it. With `size` nil the window takes the document's fitting size. The app is not
    /// activated (the user keeps focus), so controls draw in their inactive style; the layout is
    /// the same as in a shown window. Returns the capture and the warnings ActionUI logged.
    func renderDocument(_ document: JSONValue, size: NSSize?, delay: Double) async throws -> (Screenshot, [String]) {
        let loaded = try load(document: document.any as? [String: Any] ?? [:], windowID: UUID().uuidString)
        let errors = loaded.entries.filter { $0.level == .error }.map(\.message)
        guard errors.isEmpty else {
            throw MCPToolError("ActionUI could not load the document:\n" + errors.prefix(20).joined(separator: "\n"))
        }
        let window = OffscreenCaptureWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = loaded.controller.view
        window.title = "Preview"
        window.setContentSize(size ?? Self.clampedToScreen(loaded.fitting))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        let warnings = loaded.entries.filter { $0.level == .warning }.map(\.message)
        return (try screenshot(of: window, name: "render"), Array(warnings.prefix(20)))
    }

    /// Draws the window's frame view (title bar included) into a bitmap, scales it down to
    /// `maxScreenshotPixels`, and saves it as a PNG in the server's temporary folder.
    func screenshot(of window: NSWindow, name: String) throws -> Screenshot {
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
        if longest > Self.maxScreenshotPixels, let scaled = Self.scaled(image, by: Double(Self.maxScreenshotPixels) / Double(longest)) {
            image = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw MCPToolError("could not encode the screenshot")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MCPToolError("could not encode the screenshot") }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-mcp-\(ProcessInfo.processInfo.processIdentifier)/screenshots", isDirectory: true)
        let file = folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try (data as Data).write(to: file, options: .atomic)
        } catch {
            throw MCPToolError("could not save the screenshot: \(error.localizedDescription)")
        }
        Self.pruneScreenshots(in: folder)
        return Screenshot(png: data as Data, pixelWidth: image.width, pixelHeight: image.height, path: file.path)
    }

    /// Keeps the newest `keptScreenshots` files in `folder`.
    private static func pruneScreenshots(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        guard files.count > keptScreenshots else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keptScreenshots) {
            try? FileManager.default.removeItem(at: file)
        }
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
