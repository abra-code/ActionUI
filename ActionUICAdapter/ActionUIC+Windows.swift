// ActionUICAdapter/ActionUIC+Windows.swift
//
//  The Windows side of hostNative (the Apple side is in ActionUIC+Apple.swift, Linux's in
//  ActionUIC+Linux.swift): Windows builds with FoundationEssentials, which has no Foundation
//  objects, so a host's values are already Swift-native. And, as on Linux, the functions for a host
//  that runs its own WinUI application: a document in a window the host made, and the main-loop
//  bridge.
//

#if os(Windows)
import ActionUI

/// A value a host stored, as ActionUIJSON reads it: unchanged on Windows.
func hostNative(_ value: Any) -> Any {
    value
}

// MARK: - A document in a window the host made

/// Loads the document at `urlString` (a path or a file URL) into the model under `windowUUID` and
/// makes it the content of `xamlWindow`, a Microsoft.UI.Xaml.Window the host made in its own WinUI
/// application (its IInspectable pointer: winrt::get_abi(window)), and sets the window's size from the
/// document. The host shows the window and owns its title, closing and focus; closing it keeps the
/// model, which the host removes with actionUIRemoveWindow. `subtitle` is accepted and not shown yet.
/// Returns false, with an error set, when the document cannot be read or loaded (the window then shows
/// why) or the window is not a WinUI window (nothing done). Call it on the UI thread, or while it runs
/// the main queue.
@c
public func actionUILoadIntoHostWindowFromURL(_ xamlWindow: UnsafeMutableRawPointer?, _ urlString: UnsafePointer<CChar>?,
                                              _ windowUUID: UnsafePointer<CChar>?, _ subtitle: UnsafePointer<CChar>?) -> CBool {
    clearError()
    guard let xamlWindow, let urlString, let windowUUID else {
        setError("actionUILoadIntoHostWindowFromURL: the window, URL and window UUID are required")
        return false
    }
    let url = String(cString: urlString)
    let uuid = String(cString: windowUUID)
    let address = UInt(bitPattern: xamlWindow)
    let loaded = runOnMainActorSync {
        HostWindow.load(url: url, into: UnsafeMutableRawPointer(bitPattern: address)!, windowUUID: uuid)
    }
    if !loaded {
        setError("Window \(uuid): \(url) was not loaded into the host window (see the log)")
    }
    return loaded
}

/// As actionUILoadIntoHostWindowFromURL, with the document's JSON.
@c
public func actionUILoadIntoHostWindowFromJSON(_ xamlWindow: UnsafeMutableRawPointer?, _ jsonString: UnsafePointer<CChar>?,
                                               _ windowUUID: UnsafePointer<CChar>?, _ subtitle: UnsafePointer<CChar>?) -> CBool {
    clearError()
    guard let xamlWindow, let jsonString, let windowUUID else {
        setError("actionUILoadIntoHostWindowFromJSON: the window, JSON and window UUID are required")
        return false
    }
    let json = String(cString: jsonString)
    let uuid = String(cString: windowUUID)
    let address = UInt(bitPattern: xamlWindow)
    let loaded = runOnMainActorSync {
        HostWindow.load(json: json, into: UnsafeMutableRawPointer(bitPattern: address)!, windowUUID: uuid)
    }
    if !loaded {
        setError("Window \(uuid): the JSON was not loaded into the host window (see the log)")
    }
    return loaded
}

// MARK: - For a host that runs its own application

/// Starts running Swift's main-actor work (ActionUI's C calls made from other threads, actions queued
/// for later) under the host's WinUI loop now, rather than when the first window is filled: for a host
/// that does work before it fills a window. Call it on the UI thread while the host's application
/// runs; later calls do nothing.
@c
public func actionUIInstallMainLoopBridge() {
    // Not runOnMainActorSync: from another thread its wait on the main queue would be the very work
    // this installs the runner for.
    guard isMainThread else {
        setError("actionUIInstallMainLoopBridge: call it on the UI thread")
        return
    }
    clearError()
    MainActor.assumeIsolated {
        if !MainLoopBridge.install() {
            setError("actionUIInstallMainLoopBridge: the main queue could not be watched (see the log)")
        }
    }
}
#endif
