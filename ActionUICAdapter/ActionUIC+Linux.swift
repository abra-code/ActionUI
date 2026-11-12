// ActionUICAdapter/ActionUIC+Linux.swift
//
//  The Linux side of hostNative (the Apple side is in ActionUIC+Apple.swift): Linux builds with
//  FoundationEssentials, which has no Foundation objects, so a host's values are already
//  Swift-native. And the Linux counterpart of the Apple hosting controller: a document in a window
//  the host made (actionUILoadIntoHostWindowFromURL, actionUILoadIntoHostWindowFromJSON).
//

import ActionUI

/// A value a host stored, as ActionUIJSON reads it: unchanged on Linux.
func hostNative(_ value: Any) -> Any {
    value
}

// MARK: - A document in a window the host made

/// Loads the document at `urlString` (a path or a file URL) into the model under `windowUUID` and
/// fills `gtkWindow`, an AdwApplicationWindow or AdwWindow the host made and has not presented yet,
/// as ActionUI fills its own windows: the subtitle line (`subtitle` may be NULL), the header bar
/// with the document's toolbar items and the primary menu, the toast overlay, scrolling for a
/// document larger than the screen, and the document's modals, alerts and toasts on that window;
/// sets the window's default size from the document. The host presents the window and owns its
/// title, close and focus; closing it does not remove the model, which the host removes with
/// actionUIRemoveWindow. Returns false, with an error set, when the document cannot be read or
/// loaded (the window then shows why) or the window is not one ActionUI can fill (nothing done).
/// Call it from the main thread, or while the main thread runs the main queue.
@c
public func actionUILoadIntoHostWindowFromURL(_ gtkWindow: UnsafeMutableRawPointer?, _ urlString: UnsafePointer<CChar>?,
                                              _ windowUUID: UnsafePointer<CChar>?, _ subtitle: UnsafePointer<CChar>?) -> CBool {
    clearError()
    guard let gtkWindow, let urlString, let windowUUID else {
        setError("actionUILoadIntoHostWindowFromURL: the window, URL and window UUID are required")
        return false
    }
    let url = String(cString: urlString)
    let uuid = String(cString: windowUUID)
    let line = subtitle.map { String(cString: $0) }
    let address = UInt(bitPattern: gtkWindow)
    let loaded = runOnMainActorSync {
        HostWindow.load(url: url, into: UnsafeMutableRawPointer(bitPattern: address)!, windowUUID: uuid, subtitle: line)
    }
    if !loaded {
        setError("Window \(uuid): \(url) was not loaded into the host window (see the log)")
    }
    return loaded
}

/// As actionUILoadIntoHostWindowFromURL, with the document's JSON.
@c
public func actionUILoadIntoHostWindowFromJSON(_ gtkWindow: UnsafeMutableRawPointer?, _ jsonString: UnsafePointer<CChar>?,
                                               _ windowUUID: UnsafePointer<CChar>?, _ subtitle: UnsafePointer<CChar>?) -> CBool {
    clearError()
    guard let gtkWindow, let jsonString, let windowUUID else {
        setError("actionUILoadIntoHostWindowFromJSON: the window, JSON and window UUID are required")
        return false
    }
    let json = String(cString: jsonString)
    let uuid = String(cString: windowUUID)
    let line = subtitle.map { String(cString: $0) }
    let address = UInt(bitPattern: gtkWindow)
    let loaded = runOnMainActorSync {
        HostWindow.load(json: json, into: UnsafeMutableRawPointer(bitPattern: address)!, windowUUID: uuid, subtitle: line)
    }
    if !loaded {
        setError("Window \(uuid): the JSON was not loaded into the host window (see the log)")
    }
    return loaded
}

// MARK: - For a host that runs its own application

/// Starts running Swift's main-actor work (ActionUI's C calls made from other threads, the remote
/// bridge's answers) under the GLib main loop now, rather than when the first window is registered:
/// for a host that does work before it shows a window. Call it on the main thread, before or while
/// the main loop runs; later calls do nothing.
@c
public func actionUIInstallMainLoopBridge() {
    // Not runOnMainActorSync: from another thread its wait on the main queue would be the very
    // work this installs the runner for
    guard isMainThread else {
        setError("actionUIInstallMainLoopBridge: call it on the main thread")
        return
    }
    clearError()
    MainActor.assumeIsolated {
        MainLoopBridge.install()
    }
}

/// Adds the CommandMenu and CommandGroup elements in `json` (a JSON array of them, the format of
/// a macOS menu bar document) to the primary menu every window's header bar shows, as ActionUI's
/// own application loads its menu bar. Each item becomes an action of the process's default
/// GApplication (the host's own), which fires its actionID for the active window's document, with
/// its keyboard shortcut working in every window; Quit stays the host's to bind. Successive calls
/// add to the menu. Returns false, with an error set, for JSON that is not an array (elements of
/// other types in it are ignored).
@c
public func actionUILoadMenuBarJSON(_ json: UnsafePointer<CChar>?) -> CBool {
    clearError()
    guard let json else {
        setError("actionUILoadMenuBarJSON: the JSON is required")
        return false
    }
    let text = String(cString: json)
    let loaded = runOnMainActorSync {
        AppCommands.shared.load(json: text)
    }
    if !loaded {
        setError("actionUILoadMenuBarJSON: the JSON is not an array (of CommandMenu and CommandGroup elements)")
    }
    return loaded
}

/// Loads the CommandMenu and CommandGroup elements in `json` (a JSON array, as for
/// actionUILoadMenuBarJSON) under `key`, in place of the ones loaded under that key before, where
/// those were in the menu (after everything loaded so far, the first time); an empty array removes
/// them. For a part of the menu a host keeps current, such as an Open Recent submenu rebuilt when
/// the recent files change. Returns false, with an error set and the menu unchanged, for a missing
/// key or JSON that is not an array.
@c
public func actionUIReplaceMenuBarJSON(_ key: UnsafePointer<CChar>?, _ json: UnsafePointer<CChar>?) -> CBool {
    clearError()
    guard let key, let json, key.pointee != 0 else {
        setError("actionUIReplaceMenuBarJSON: the key and the JSON are required")
        return false
    }
    let keyText = String(cString: key)
    let text = String(cString: json)
    let loaded = runOnMainActorSync {
        AppCommands.shared.load(json: text, replacing: keyText)
    }
    if !loaded {
        setError("actionUIReplaceMenuBarJSON: the JSON is not an array (of CommandMenu and CommandGroup elements)")
    }
    return loaded
}

/// The height of the bars ActionUI put above the document's content in the window showing
/// `windowUUID` (the header bar, and the subtitle line when there is one), measured when it was
/// filled, for a host's window or one ActionUI's own application presents: what a host adds to a
/// size below the bars (a layout size, a document's minimum) to get the window's size. A bottom
/// toolbar (toolbar items placed at bottomBar), which shows below the content after the window is
/// filled, is not included, as ActionUI's own opening size leaves it out. -1, with an error set,
/// when no window shows that UUID.
@c
public func actionUIGetWindowBarsHeight(_ windowUUID: UnsafePointer<CChar>?) -> Double {
    clearError()
    guard let windowUUID else {
        setError("actionUIGetWindowBarsHeight: the window UUID is required")
        return -1
    }
    let uuid = String(cString: windowUUID)
    let height = runOnMainActorSync {
        WindowRegistry.shared.barsHeight(uuid)
    }
    guard let height else {
        setError("actionUIGetWindowBarsHeight: no window shows \(uuid)")
        return -1
    }
    return Double(height)
}
