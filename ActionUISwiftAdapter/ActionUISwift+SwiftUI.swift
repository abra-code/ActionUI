//
//  ActionUISwift+SwiftUI.swift
//  ActionUISwiftAdapter
//
//  The parts of ActionUISwift that hand out SwiftUI views and hosting controllers (Apple only;
//  the rest, in ActionUISwift.swift, also builds on Linux).
//

import ActionUI
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension ActionUISwift {
    private static var model: ActionUI.ActionUIModel { ActionUI.ActionUIModel.shared }

    /// Loads a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: A SwiftUI view loaded from the description.
    /// Design decision: Determines local vs. remote based on URL scheme; uses FileLoadableView for local (sync) and RemoteLoadableView for remote (async with ProgressView).
    public static func loadView(from url: URL, windowUUID: String, isContentView: Bool) -> any SwiftUI.View {
        let logger = model.logger
        if url.scheme == "file" {
            return ActionUI.FileLoadableView(fileURL: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        } else {
            return ActionUI.RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        }
    }
    
    #if canImport(AppKit)
    /// Loads an NSHostingController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: An NSHostingController with the loaded SwiftUI view embedded as its root view.
    /// Design decision: Wraps the view from loadView in an NSHostingController for macOS integration.
    public static func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> NSHostingController<AnyView> {
        let view = loadView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        return NSHostingController(rootView: AnyView(view))
    }

    /// Returns the size limits of a loaded window's root element content: minSize for a zero
    /// size proposal, maxSize for an infinite one. Content with a fixed root frame reports
    /// minSize == maxSize, which lets an AppKit host make its window non-user-resizable.
    /// Measures the bare root element (bypassing the window-level modal/toast wrapper, which
    /// always expands to fill). Call after the window's description has been loaded.
    /// - Parameter windowUUID: Unique identifier for the window.
    /// - Returns: The content's size limits, or nil when the window or its root element is unknown.
    public static func contentSizeLimits(windowUUID: String) -> ActionUI.ContentSizeLimits? {
        return model.contentSizeLimits(windowUUID: windowUUID)
    }
    #endif // canImport(AppKit)
    
    #if canImport(UIKit)
    /// Loads a UIHostingController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: A UIHostingController with the loaded SwiftUI view embedded as its root view.
    /// Design decision: Wraps the view from loadView in a UIHostingController for iOS/iPadOS/tvOS/visionOS/watchOS integration.
    public static func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> UIHostingController<AnyView> {
        let view = loadView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        return UIHostingController(rootView: AnyView(view))
    }
    #endif // canImport(UIKit)
}
