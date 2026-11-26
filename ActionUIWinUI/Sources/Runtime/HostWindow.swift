// Sources/Runtime/HostWindow.swift
/*
 ActionUI JSON in a window a host made in its own WinUI application (the C adapter's
 actionUILoadIntoHostWindowFromURL and FromJSON), as Linux's HostWindow fills a host's GTK window and
 Apple's hosting controller goes into a host's AppKit window: its root element becomes the window's content
 and the window's size is set from it (WinUIWindow.openingSize), again once the content has loaded
 (WinUIWindow.fit; the window is cloaked until then). The host shows the window and owns its title,
 closing and focus. When the window closes, the UI's nodes leave the tree; its model
 stays until the host removes it (actionUIRemoveWindow), as on Linux. ActionUI JSON that cannot be loaded
 is logged and shown as its error text in the window.

 Main-actor work runs under the host's loop once MainLoopBridge is installed: filling a window
 installs it, as does actionUIInstallMainLoopBridge for a host that needs it sooner.

 Not yet: the subtitle line (accepted, not shown).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

@MainActor
package enum HostWindow {
    /// One host window and the tree of its ActionUI JSON.
    private final class Filled {
        let window: WinUIObject
        let tree: WinUIWindow

        init(window: WinUIObject, tree: WinUIWindow) {
            self.window = window
            self.tree = tree
        }
    }

    /// The host windows filled, by window UUID.
    private static var filled: [String: Filled] = [:]

    /// Loads the ActionUI JSON at `url` (a path or a file URL) into the host's window `window` (a
    /// Microsoft.UI.Xaml.Window's IInspectable pointer): false when the ActionUI JSON cannot be loaded (the
    /// window then shows why) or `window` is no WinUI window (nothing done).
    package static func load(url text: String, into window: UnsafeMutableRawPointer, windowUUID: String) -> Bool {
        let fileURL: URL
        if let parsed = URL(string: text), let scheme = parsed.scheme, scheme.count > 1 {
            guard parsed.isFileURL else {
                ActionUIModel.shared.logger.log("HostWindow: \(text) is not a file; only files are loaded into a host's window", .error)
                return fill(window, windowUUID: windowUUID) {
                    throw ActionUIError("only files are loaded into a host's window on Windows yet (\(text))")
                }
            }
            fileURL = parsed
        } else {
            fileURL = URL(fileURLWithPath: text)
        }
        return fill(window, windowUUID: windowUUID, fileName: fileURL.lastPathComponent) {
            try WinUIWindow.load(file: fileURL, windowUUID: windowUUID)
        }
    }

    /// As load(url:into:windowUUID:), with the ActionUI JSON itself (the host's own).
    package static func load(json: String, into window: UnsafeMutableRawPointer, windowUUID: String) -> Bool {
        fill(window, windowUUID: windowUUID) { try WinUIWindow.load(json: json, windowUUID: windowUUID) }
    }

    /// Fills the host's window with the tree `load` makes, or with the error it throws, as text: false
    /// for an error, or when the window is no WinUI window or cannot be filled.
    private static func fill(_ pointer: UnsafeMutableRawPointer, windowUUID: String, fileName: String? = nil,
                             _ load: () throws -> WinUIWindow) -> Bool {
        let logger = ActionUIModel.shared.logger
        guard let window = WinUIObject(adopting: actionUIWinUIWindowFromInspectable(pointer)) else {
            logger.log("HostWindow: \(WinUIError.last("taking the host's window for \(windowUUID)"))", .error)
            return false
        }
        // The host runs the loop: main-actor work runs under it from now on.
        MainLoopBridge.install()
        // A window already filled under the UUID leaves first (the same WindowModel takes the new ActionUI JSON).
        if let earlier = filled.removeValue(forKey: windowUUID) {
            earlier.tree.detach()
        }
        var loaded = true
        let tree: WinUIWindow
        do {
            tree = try load()
        } catch {
            loaded = false
            logger.log("HostWindow: window \(windowUUID) could not be loaded: \(error)", .error)
            guard let errorTree = WinUIWindow.loadError(error, fileName: fileName, windowUUID: windowUUID) else { return false }
            tree = errorTree
        }
        guard let content = tree.view, actionUIWinUIWindowSetContent(window.pointer, content.pointer),
              case let size = tree.openingSize(),
              actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height) else {
            logger.log("HostWindow: \(WinUIError.last("filling the host's window for \(windowUUID)"))", .error)
            tree.detach()
            return false
        }
        // Cloaked until sized to its content once loaded (WinUIWindow.fit): the size above is measured before
        // the controls have their styles.
        tree.fit(window, wanted: nil, cloaks: true)
        let entry = Filled(window: window, tree: tree)
        filled[windowUUID] = entry
        WinUIEvents.connect(window, actionUIWinUIWindowOnClosed, "a host window's closing") { [weak entry] in
            // Only the ActionUI JSON still in it: one filled again under the UUID is the newer one's.
            guard let entry, filled[windowUUID] === entry else { return }
            filled[windowUUID] = nil
            entry.tree.detach()
        }
        return loaded
    }
}
