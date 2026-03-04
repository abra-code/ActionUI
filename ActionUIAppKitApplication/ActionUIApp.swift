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
import UniformTypeIdentifiers

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
private var windowWillPresentHandler:   ActionUIAppWindowHandler? = nil

// MARK: - Application name (set before run)

/// Custom application name.  When set, overrides processName in the menu bar.
var appName: String? = nil

/// Custom application icon.  Applied in actionUIAppRun before
/// setActivationPolicy(.regular) so the dock picks it up immediately.
var appIcon: NSImage? = nil

// MARK: - Window registry (UUID to NSWindow)

private var windows: [String: NSWindow] = [:]

// MARK: - Application delegate

final class ActionUIApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static let shared = ActionUIApplicationDelegate()

    // MARK: NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Install the default menu bar before the user's handler fires,
        // so the menu bar is visible by the time didFinishLaunching runs.
        // Always reinstall when appName is set — a menu bar may have been
        // loaded earlier (e.g. by actionUIAppLoadMenuBar) before the
        // caller set the app name, so the titles would be stale.
        let app = NSApplication.shared
        if appName != nil || app.mainMenu == nil || app.mainMenu?.items.isEmpty == true {
            installDefaultMenuBar(appName: appName)
        }

        willFinishLaunchingHandler?()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-apply the custom icon after the window server has fully
        // registered the process — catches any reset during launch.
        if let icon = appIcon {
            NSApplication.shared.applicationIconImage = icon
        }

        didFinishLaunchingHandler?()

        // Bring the app to front.  Delayed so the window server has time
        // to fully register the process after setActivationPolicy(.regular).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate()
            for window in NSApp.windows where window.isVisible {
                window.orderFrontRegardless()
            }
        }
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

    // MARK: About panel

    @objc func showAboutPanel(_ sender: Any?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            // Suppress inherited version / copyright from the host bundle
            .version: "1.0",
            .init(rawValue: "Copyright"): "",
        ]

        // Show the custom icon if one was set via actionUIAppSetIcon.
        if let icon = appIcon {
            options[.applicationIcon] = icon
        }

        // Show the custom app name if one was set via actionUIAppSetName.
        if let name = appName {
            options[.applicationName] = name
        }

        // Credits line — rendered as attributed string in the About panel.
        let credits = NSAttributedString(
            string: "Application created with ActionUI\nhttps://github.com/abra-code/ActionUI",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        options[.credits] = credits

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
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

@_cdecl("actionUIAppSetWindowWillPresentHandler")
public func actionUIAppSetWindowWillPresentHandler(_ handler: ActionUIAppWindowHandler?) {
    windowWillPresentHandler = handler
}

// MARK: - App name

/// Set the application name used in the menu bar (About, Hide, Quit).
/// You only want to do it if you are launching an unbundled app
/// In regular bundled app, don't use this API - it erases infoDictionary and sets CFBundleName only
/// Must be called before `actionUIAppRun()`.
/// Also sets `ProcessInfo.processInfo.processName` so the system picks it up.
@_cdecl("actionUIAppSetName")
public func actionUIAppSetName(_ name: UnsafePointer<CChar>) {
    let swiftAppName = String(cString: name)
    appName = swiftAppName
    ProcessInfo.processInfo.processName = swiftAppName

    // Patch the main bundle's info dictionary so macOS picks up the
    // custom name for the app menu title.  The underlying NSDictionary
    // returned by -[NSBundle infoDictionary] is actually mutable at
    // runtime — this is the standard trick for unbundled processes
    // (e.g. Python scripts) that don't have their own Info.plist.
    
    if let info = Bundle.main.infoDictionary as NSDictionary?,
       let mutable = info as? NSMutableDictionary {
        mutable.removeAllObjects()
        mutable["CFBundleName"] = swiftAppName
    }
}

// MARK: - App icon

/// Set the application icon (Dock + About panel).
/// Takes a filesystem path to an image file (PNG, ICNS, TIFF, etc.).
/// Must be called before `actionUIAppRun()`.
///
/// Patches the main bundle's info dictionary to remove `CFBundleIconFile`
/// and `CFBundleIconName` so the standard About panel (and the dock for
/// framework-style Python) fall back to `applicationIconImage` instead of
/// the host executable's icon (e.g. Python.app's rocket).
@_cdecl("actionUIAppSetIcon")
public func actionUIAppSetIcon(_ path: UnsafePointer<CChar>) {
    let swiftPath = String(cString: path)
    guard let image = NSImage(contentsOfFile: swiftPath) else { return }
    appIcon = image

    // Register under the well-known application icon name so that
    // AppKit APIs that fetch the icon by name (e.g. the standard
    // About panel via NSImage(named: .applicationIcon)) return our
    // image instead of the host bundle's icon.
    // NSImage.setName(_:) requires removing any previous image
    // registered under that name first.
    if let old = NSImage(named: NSImage.applicationIconName) {
        old.setName(nil as NSImage.Name?)
    }
    image.setName(NSImage.applicationIconName)

    // If the run loop is already active, apply immediately.
    runOnMainActorAsync {
        NSApplication.shared.applicationIconImage = image
    }
}

// MARK: - App control

/// Start the NSApplication run loop.  Blocks until the app terminates.
/// Must be called from the main thread.
@_cdecl("actionUIAppRun")
public func actionUIAppRun() {
    let app = NSApplication.shared

    // Apply the custom icon *before* setActivationPolicy so the dock shows
    // it from the moment the app appears, rather than flashing the default
    // icon first.  For non-framework Python (no .app bundle) this is the
    // only opportunity — once the activation policy is set, the window
    // server has already latched the icon.
    if let icon = appIcon {
        app.applicationIconImage = icon
    }

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
        // the close animation with a dangling pointer, causing SIGSEGV.
        window.isReleasedWhenClosed  = false
        window.title                 = swiftTitle ?? url.deletingPathExtension().lastPathComponent
        window.contentViewController = controller
        window.setContentSize(windowSize)
        window.center()
        window.delegate = ActionUIApplicationDelegate.shared

        windows[swiftUUID] = window
        if let handler = windowWillPresentHandler {
            swiftUUID.withCString { handler($0) }
        }
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

// MARK: - String duplication helper (file-private)

/// Duplicate a Swift String into a malloc'd C string.  Caller owns the memory
/// and must free it via `actionUIFreeString` (which calls `free(3)`).
@inline(__always)
private func actionStrdup(_ string: String) -> UnsafeMutablePointer<CChar> {
    return string.withCString { strdup($0)! }
}

// MARK: - File panels (NSOpenPanel / NSSavePanel)

/// Parse a JSON config dictionary and configure an `NSOpenPanel`.
/// Returns the panel result as a JSON array of file paths, or `nil` if cancelled.
///
/// Config JSON keys (all optional):
///   title, prompt, message, identifier,
///   allowedContentTypes: [String],  // file extensions ("json") or UTI strings ("public.image")
///   allowsMultipleSelection: Bool,
///   canChooseDirectories: Bool,
///   canChooseFiles: Bool,
///   directoryURL: String,
///   showsHiddenFiles: Bool,
///   treatsFilePackagesAsDirectories: Bool,
///   canCreateDirectories: Bool,
///   allowsOtherFileTypes: Bool
@_cdecl("actionUIAppRunOpenPanel")
public func actionUIAppRunOpenPanel(
    _ configJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let jsonString = configJSON.map { String(cString: $0) }
    return runOnMainActorSync {
        let config = parseFilePanelConfig(jsonString)

        let panel = NSOpenPanel()
        applyCommonPanelConfig(panel, config: config)

        panel.allowsMultipleSelection         = config["allowsMultipleSelection"] as? Bool ?? false
        panel.canChooseDirectories             = config["canChooseDirectories"] as? Bool ?? false
        panel.canChooseFiles                   = config["canChooseFiles"] as? Bool ?? true

        let response = panel.runModal()
        guard response == .OK else { return nil }

        let paths = panel.urls.map { $0.path }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: paths),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return nil }

        return actionStrdup(jsonString)
    }
}

/// Parse a JSON config dictionary and configure an `NSSavePanel`.
/// Returns the chosen file path as a C string, or `nil` if cancelled.
///
/// Config JSON keys (all optional):
///   title, prompt, message, identifier,
///   allowedContentTypes: [String],
///   nameFieldStringValue: String,  // default filename
///   directoryURL: String,
///   showsHiddenFiles: Bool,
///   treatsFilePackagesAsDirectories: Bool,
///   canCreateDirectories: Bool,
///   allowsOtherFileTypes: Bool
@_cdecl("actionUIAppRunSavePanel")
public func actionUIAppRunSavePanel(
    _ configJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let jsonString = configJSON.map { String(cString: $0) }
    return runOnMainActorSync {
        let config = parseFilePanelConfig(jsonString)

        let panel = NSSavePanel()
        applyCommonPanelConfig(panel, config: config)

        if let filename = config["nameFieldStringValue"] as? String {
            panel.nameFieldStringValue = filename
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }

        return actionStrdup(url.path)
    }
}

// MARK: - File panel helpers (private)

/// Parse optional JSON config into a dictionary.  Returns empty dict on nil or parse failure.
private func parseFilePanelConfig(_ jsonString: String?) -> [String: Any] {
    guard let jsonString else { return [:] }
    guard let data = jsonString.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let dict = obj as? [String: Any]
    else { return [:] }
    return dict
}

/// Apply common NSSavePanel configuration from a parsed JSON dict.
@MainActor
private func applyCommonPanelConfig(_ panel: NSSavePanel, config: [String: Any]) {
    if let title = config["title"] as? String {
        panel.title = title
    }
    if let prompt = config["prompt"] as? String {
        panel.prompt = prompt
    }
    if let message = config["message"] as? String {
        panel.message = message
    }
    if let identifier = config["identifier"] as? String {
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
    }
    if let typeStrings = config["allowedContentTypes"] as? [String] {
        var types: [UTType] = []
        for str in typeStrings {
            if let t = UTType(filenameExtension: str) {
                types.append(t)
            } else if let t = UTType(str) {
                types.append(t)
            }
        }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
    }
    if let dirPath = config["directoryURL"] as? String {
        panel.directoryURL = URL(fileURLWithPath: dirPath)
    }
    if let v = config["showsHiddenFiles"] as? Bool {
        panel.showsHiddenFiles = v
    }
    if let v = config["treatsFilePackagesAsDirectories"] as? Bool {
        panel.treatsFilePackagesAsDirectories = v
    }
    if let v = config["canCreateDirectories"] as? Bool {
        panel.canCreateDirectories = v
    }
    if let v = config["allowsOtherFileTypes"] as? Bool {
        panel.allowsOtherFileTypes = v
    }
}
