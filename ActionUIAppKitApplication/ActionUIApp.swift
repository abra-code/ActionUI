// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIApp.swift
//  ActionUIAppKitApplication
//
//  AppKit application lifecycle adapter.
//
//  Provides @_cdecl C functions that let non-Swift callers (e.g. Python)
//  configure NSApplication lifecycle callbacks and start the run loop.
//  The app is a singleton — no object pointer is exposed to the caller;
//  windows are identified only by caller-supplied UUID strings.
//

import AppKit
import Foundation
import ActionUI
import SwiftUI

#if SWIFT_PACKAGE
import ActionUIAppKitApplicationHeaders
#endif

// MARK: - Main-actor dispatch helpers

/// Execute *operation* on the main actor asynchronously.
/// Safe to call from any thread.
@inline(__always)
private func runOnMainActorAsync(_ operation: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { operation() }
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { operation() }
        }
    }
}

/// Execute *operation* on the main actor synchronously and return its result.
/// Safe to call from any thread (deadlock-protected: caller must not hold
/// the main queue's lock).
@inline(__always)
private func runOnMainActorSync<T>(_ operation: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { operation() }
    } else {
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { operation() }
        }
    }
}

// MARK: - Registered C callbacks (module-level singletons)

private var willFinishLaunchingHandler: ActionUIAppLifecycleHandler? = nil
private var didFinishLaunchingHandler:  ActionUIAppLifecycleHandler? = nil
private var willBecomeActiveHandler:    ActionUIAppLifecycleHandler? = nil
private var didBecomeActiveHandler:     ActionUIAppLifecycleHandler? = nil
private var willResignActiveHandler:    ActionUIAppLifecycleHandler? = nil
private var didResignActiveHandler:     ActionUIAppLifecycleHandler? = nil
private var willTerminateHandler:       ActionUIAppLifecycleHandler? = nil
private var shouldTerminateHandler:     ActionUIAppShouldTerminateHandler? = nil
private var windowWillCloseHandler:     ActionUIAppWindowHandler? = nil

// MARK: - Window registry (UUID → NSWindow)

private var windows: [String: NSWindow] = [:]

// MARK: - Application delegate

final class ActionUIApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static let shared = ActionUIApplicationDelegate()

    // MARK: NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        willFinishLaunchingHandler?()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunchingHandler?()
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        willBecomeActiveHandler?()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        didBecomeActiveHandler?()
    }

    func applicationWillResignActive(_ notification: Notification) {
        willResignActiveHandler?()
    }

    func applicationDidResignActive(_ notification: Notification) {
        didResignActiveHandler?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        willTerminateHandler?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let handler = shouldTerminateHandler else { return .terminateNow }
        return handler() ? .terminateNow : .terminateCancel
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let uuid = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: uuid)
        if let handler = windowWillCloseHandler {
            uuid.withCString { handler($0) }
        }
    }
}

// MARK: - Lifecycle handler registration

@_cdecl("actionUIAppSetWillFinishLaunchingHandler")
public func actionUIAppSetWillFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    willFinishLaunchingHandler = handler
}

@_cdecl("actionUIAppSetDidFinishLaunchingHandler")
public func actionUIAppSetDidFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    didFinishLaunchingHandler = handler
}

@_cdecl("actionUIAppSetWillBecomeActiveHandler")
public func actionUIAppSetWillBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    willBecomeActiveHandler = handler
}

@_cdecl("actionUIAppSetDidBecomeActiveHandler")
public func actionUIAppSetDidBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    didBecomeActiveHandler = handler
}

@_cdecl("actionUIAppSetWillResignActiveHandler")
public func actionUIAppSetWillResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    willResignActiveHandler = handler
}

@_cdecl("actionUIAppSetDidResignActiveHandler")
public func actionUIAppSetDidResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    didResignActiveHandler = handler
}

@_cdecl("actionUIAppSetWillTerminateHandler")
public func actionUIAppSetWillTerminateHandler(_ handler: ActionUIAppLifecycleHandler?) {
    willTerminateHandler = handler
}

@_cdecl("actionUIAppSetShouldTerminateHandler")
public func actionUIAppSetShouldTerminateHandler(_ handler: ActionUIAppShouldTerminateHandler?) {
    shouldTerminateHandler = handler
}

@_cdecl("actionUIAppSetWindowWillCloseHandler")
public func actionUIAppSetWindowWillCloseHandler(_ handler: ActionUIAppWindowHandler?) {
    windowWillCloseHandler = handler
}

// MARK: - App control

/// Start the NSApplication run loop.  Blocks until the app terminates.
/// Must be called from the main thread.
@_cdecl("actionUIAppRun")
public func actionUIAppRun() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = ActionUIApplicationDelegate.shared
    app.run()
}

/// Request graceful termination (equivalent to Cmd-Q).
@_cdecl("actionUIAppTerminate")
public func actionUIAppTerminate() {
    runOnMainActorAsync {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Window operations

/// Load an ActionUI JSON view from `urlString` and present it in a new window.
///
/// - Parameters:
///   - urlString:  file:// or http(s):// URL of the ActionUI JSON definition.
///   - windowUUID: Caller-supplied UUID; used as the ActionUI window identifier
///                 for all subsequent value and state operations.
///   - title:      Window title.  Pass NULL to derive from the URL filename.
///
/// Window size is set to the SwiftUI view's fitting size; falls back to
/// 480×320 if the view has not yet laid out (common for async JSON loads).
/// Safe to call from applicationDidFinishLaunching — runs on the main thread.
@_cdecl("actionUIAppLoadAndPresentWindow")
public func actionUIAppLoadAndPresentWindow(
    _ urlString: UnsafePointer<CChar>,
    _ windowUUID: UnsafePointer<CChar>,
    _ title: UnsafePointer<CChar>?
) {
    let swiftURLString = String(cString: urlString)
    let swiftUUID      = String(cString: windowUUID)
    let swiftTitle     = title.map { String(cString: $0) }

    guard let url = URL(string: swiftURLString) else {
        runOnMainActorAsync {
            ActionUIModel.shared.logger.log(
                "actionUIAppLoadAndPresentWindow: invalid URL '\(swiftURLString)'", .error)
        }
        return
    }

    runOnMainActorSync {
        let logger = ActionUIModel.shared.logger
        let view: any View = url.scheme == "file"
            ? ActionUI.FileLoadableView(fileURL: url, windowUUID: swiftUUID,
                                        isContentView: true, logger: logger)
            : ActionUI.RemoteLoadableView(url: url, windowUUID: swiftUUID,
                                          isContentView: true, logger: logger)

        let controller = NSHostingController(rootView: AnyView(view))
        controller.view.autoresizingMask = [.width, .height]

        // Use the SwiftUI fitting size; fall back if the view has not yet laid out.
        let fittingSize = controller.view.fittingSize
        let windowSize  = (fittingSize.width >= 10 && fittingSize.height >= 10)
            ? fittingSize
            : NSSize(width: 480, height: 320)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        // ARC manages the window's lifetime via the `windows` dictionary.
        // The default (isReleasedWhenClosed = true) would cause AppKit to
        // call an extra -release on close, conflicting with ARC and leaving
        // the close animation with a dangling pointer → SIGSEGV.
        window.isReleasedWhenClosed  = false
        window.title                 = swiftTitle ?? url.deletingPathExtension().lastPathComponent
        window.contentViewController = controller
        window.setContentSize(windowSize)
        window.center()
        window.delegate = ActionUIApplicationDelegate.shared

        windows[swiftUUID] = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

/// Close the window identified by `windowUUID`.
/// The windowWillClose handler fires as normal before the window is removed.
@_cdecl("actionUIAppCloseWindow")
public func actionUIAppCloseWindow(_ windowUUID: UnsafePointer<CChar>) {
    let uuid = String(cString: windowUUID)
    runOnMainActorAsync {
        windows[uuid]?.close()
    }
}
