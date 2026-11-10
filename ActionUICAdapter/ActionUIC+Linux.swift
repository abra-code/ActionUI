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
