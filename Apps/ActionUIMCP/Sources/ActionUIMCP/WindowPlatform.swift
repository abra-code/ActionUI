// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowPlatform.swift - what the window host needs from the windowing system. WindowHost and its
// extensions hold what works the same everywhere: the event queue, waiters, dialog sessions, values,
// updates and the handoff of kept windows. Behind this protocol, a layer for each windowing system
// opens, closes and captures the windows. Each layer is in files of its own; HostPlatform names the
// one this build uses.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(AppKit)
typealias HostPlatform = AppKitPlatform
#endif

/// A size in points.
struct ContentSize: Sendable, Equatable {
    var width: Double
    var height: Double
}

/// A window drawn to a PNG, no more than WindowHost.maxScreenshotPixels on its longest side.
struct CapturedImage {
    let png: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

/// What a keeper process needs to show an open window again.
struct KeptWindowState {
    let id: String
    let title: String
    let subtitle: String
    /// x, y, width, height of the window frame, in screen coordinates. A system that does not
    /// tell applications where their windows are gives 0 for x and y.
    let frame: [Double]
    /// The layer's own description of the window's style; only that layer reads it back.
    let styleMask: UInt
}

@MainActor
protocol WindowPlatform: AnyObject {
    /// A document built and ready to show.
    associatedtype Content
    /// A file type a panel can be limited to.
    associatedtype FileType: Sendable

    /// The layer tells the host when a window closes, whoever closed it, and may use it to load
    /// documents of its own.
    var host: WindowHost? { get set }

    /// False when no window can appear (no graphical session); a dialog would then wait forever.
    var hasGraphicalSession: Bool { get }

    /// Builds the document in `file`. The host calls this inside its log capture, so anything that
    /// reports problems in the document has to run here. The file can go once this returns.
    func loadContent(file: URL, windowID: String) -> Content

    /// Opens a window showing `content`. `activate` takes the keyboard focus (a dialog needs an
    /// answer); otherwise the window leaves it with the user where the system allows that.
    func present(_ content: Content, windowID: String, title: String, subtitle: String, sizing: WindowHost.Sizing, activate: Bool)

    /// Closes the window, and calls `host.windowClosed` once it is going. A window not ready to
    /// close yet still closes: the host has told the agent it did.
    func close(_ windowID: String)

    /// Called when anything of the server comes on screen or the last of it goes.
    func setShowsInterface(_ shows: Bool)

    /// Draws an open window, which may have opened a moment ago and not be drawn yet.
    func capture(_ windowID: String) async throws -> CapturedImage

    /// Draws `content` where the user never sees it, after `delay` seconds. With `size` nil, at
    /// the document's own size.
    func renderOffscreen(_ content: Content, size: ContentSize?, delay: Double) async throws -> CapturedImage

    /// Shows a short notice for `duration` seconds, without taking the focus.
    func showNotice(title: String?, message: String, subtitle: String, duration: Double) throws

    /// The file type for `name`, an extension or a type identifier, without a leading dot. nil
    /// when there is no such type.
    nonisolated static func fileType(named name: String) -> FileType?

    /// Shows a file panel and returns at once with a closure that cancels it. Other tool calls
    /// are served meanwhile. `completion` runs once, with the chosen paths, or nil when the panel
    /// was canceled.
    func beginPanel(_ spec: PanelSpec, completion: @escaping @MainActor ([String]?) -> Void) -> @MainActor () -> Void

    /// The state of the windows in `ids`, back to front where the system tells the order.
    func keptWindowStates(_ ids: [String]) -> [KeptWindowState]
}
