// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost+Capture.swift - screenshots of an open window, or of a document rendered where the
// user never sees it. The platform layer draws them; this keeps them in the server's temporary
// folder.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import MCPStdio

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
        guard windows.contains(windowID) else {
            throw MCPToolError("window \(windowID) was closed before it could be captured")
        }
        return try save(await platform.capture(windowID), name: "window")
    }

    /// Renders `document` where the user never sees it and captures it after `delay` seconds. With
    /// `size` nil it takes the document's fitting size. The user keeps focus, so controls draw in
    /// their inactive style; the layout is the same as in a shown window. Returns the capture and
    /// the warnings ActionUI logged.
    func renderDocument(_ document: JSONValue, size: ContentSize?, delay: Double) async throws -> (Screenshot, [String]) {
        let windowID = UUID().uuidString
        let loaded = try load(document: document.any as? [String: Any] ?? [:], windowID: windowID)
        defer { forgetModel(windowID) }
        let errors = loaded.entries.filter { $0.level == .error }.map(\.message)
        guard errors.isEmpty else {
            throw MCPToolError("ActionUI could not load the document:\n" + errors.prefix(20).joined(separator: "\n"))
        }
        let image = try await platform.renderOffscreen(loaded.content, size: size, delay: delay)
        let warnings = loaded.entries.filter { $0.level == .warning }.map(\.message)
        return (try save(image, name: "render"), Array(warnings.prefix(20)))
    }

    /// Saves a capture as a PNG in the server's temporary folder.
    func save(_ image: CapturedImage, name: String) throws -> Screenshot {
        let folder = HostSupport.sessionFolder.appendingPathComponent("screenshots", isDirectory: true)
        let file = folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.png.write(to: file, options: .atomic)
        } catch {
            throw MCPToolError("could not save the screenshot: \(error.displayText)")
        }
        Self.pruneScreenshots(in: folder)
        return Screenshot(png: image.png, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, path: file.path)
    }

    /// Keeps the newest `keptScreenshots` files in `folder`. Each file is written once, so its
    /// modification date is when it was made.
    private static func pruneScreenshots(in folder: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard names.count > keptScreenshots else { return }
        let dated = names.map { name in
            let file = folder.appendingPathComponent(name)
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            return (file, attributes?[.modificationDate] as? Date ?? .distantPast)
        }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keptScreenshots) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
