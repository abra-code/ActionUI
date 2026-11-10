// Sources/Runtime/HostWindow.swift
/*
 A document in a window the host made, for a host that runs its own GtkApplication (the C calls
 actionUILoadIntoHostWindowFromURL and actionUILoadIntoHostWindowFromJSON, ActionUIC.h), the
 counterpart of the hosting controller an AppKit host puts in its own NSWindow on macOS.

 The window is an AdwApplicationWindow or an AdwWindow, not yet presented. ActionUI fills it as it
 fills its own windows (WindowAssembly) and registers it (WindowRegistry: menu commands, content
 size limits, presentations), and sets its default size from the document. The rest is the host's:
 presenting, the title, closing, focus, modal runs. The window's model is the host's too: closing
 or destroying the window does not remove it, so the host's code can still read the values; the
 host removes it with actionUIRemoveWindow. The window leaves the registry when it is destroyed.

 Not here, unlike ActionUI's own windows: WindowGroup documents (a window's content is the document;
 a host makes its windows and loads its menu itself), http and https URLs (a file path or file URL
 only), and the check before showing (prepareWindow).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
package enum HostWindow {
    /// Loads the document at `urlString` (a path or a file URL) into the model under `windowUUID`
    /// and fills `window`; false when it cannot be read or loaded (the window then shows why) or
    /// `window` is not an AdwApplicationWindow or AdwWindow (nothing is done then).
    package static func load(url urlString: String, into window: UnsafeMutableRawPointer, windowUUID: String,
                             subtitle: String?) -> Bool {
        let url: URL
        if urlString.lowercased().hasPrefix("file://"), let fileURL = URL(string: urlString) {
            url = fileURL
        } else {
            url = URL(fileURLWithPath: urlString)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return fill(window, windowUUID: windowUUID, subtitle: subtitle, documentFolder: nil,
                        loadError: "\(url.path) could not be read: \(error)", load: nil)
        }
        return fill(window, windowUUID: windowUUID, subtitle: subtitle,
                    documentFolder: url.deletingLastPathComponent().path, loadError: nil) {
            try ActionUIModel.shared.loadWindowDocument(data, format: AppBundle.documentFormat(of: url), windowUUID: windowUUID)
        }
    }

    /// As load(url:...), with the document's JSON.
    package static func load(json: String, into window: UnsafeMutableRawPointer, windowUUID: String,
                             subtitle: String?) -> Bool {
        fill(window, windowUUID: windowUUID, subtitle: subtitle, documentFolder: nil, loadError: nil) {
            try ActionUIModel.shared.loadWindowDocument(Data(json.utf8), format: "json", windowUUID: windowUUID)
        }
    }

    /// Whether `window` is a window ActionUI can fill: an AdwApplicationWindow or an AdwWindow (an
    /// AdwApplicationWindow is not an AdwWindow, so both are asked), whose content is an
    /// AdwToolbarView and which hosts libadwaita's dialogs.
    private static func isFillable(_ window: UnsafeMutableRawPointer) -> Bool {
        let instance = window.assumingMemoryBound(to: GTypeInstance.self)
        return g_type_check_instance_is_a(instance, adw_application_window_get_type()) != 0
            || g_type_check_instance_is_a(instance, adw_window_get_type()) != 0
    }

    private static func fill(_ rawWindow: UnsafeMutableRawPointer, windowUUID: String, subtitle: String?,
                             documentFolder: String?, loadError: String?, load: (() throws -> Void)?) -> Bool {
        let logger = ActionUIModel.shared.logger
        guard isFillable(rawWindow) else {
            logger.log("Window \(windowUUID): a host window must be an AdwApplicationWindow or an AdwWindow; nothing loaded", .error)
            return false
        }
        let window: UnsafeMutablePointer<GtkWindow> = rawWindow.assumingMemoryBound(to: GtkWindow.self)

        // A file's folder is where its LoadableViews find their names.
        AppBundle.setDocumentFolder(documentFolder, window: windowUUID)
        var error = loadError
        if error == nil, let load {
            do {
                try load()
            } catch let thrown {
                error = "The document could not be loaded: \(thrown)"
            }
        }
        if let error {
            logger.log("Window \(windowUUID): \(error)", .error)
        }
        let renderTree = error == nil ? AdwaitaWindow.forWindow(windowUUID) : nil
        let content = renderTree?.contentWidget ?? WindowAssembly.errorContent(error ?? "The document has no content")

        let toolbar = adw_toolbar_view_new()!
        let instance = rawWindow.assumingMemoryBound(to: GTypeInstance.self)
        if g_type_check_instance_is_a(instance, adw_application_window_get_type()) != 0 {
            adw_application_window_set_content(typed(window), toolbar)
        } else {
            adw_window_set_content(typed(window), toolbar)
        }
        let size = WindowAssembly.assemble(window, toolbar: toolbar, content: content, renderTree: renderTree,
                                           windowUUID: windowUUID, subtitle: subtitle, contentSize: nil, presents: true)
        gtk_window_set_default_size(window, size.width, size.height)
        WindowRegistry.shared.register(windowUUID, window: window, renderTree: renderTree)
        connectSignal(rawWindow, "destroy", .instanceOnly) {
            // Only while this window is the one under the UUID: a newer one keeps its folder.
            if WindowRegistry.shared.gtkWindow(windowUUID) == nil || WindowRegistry.shared.gtkWindow(windowUUID) == window {
                AppBundle.setDocumentFolder(nil, window: windowUUID)
            }
        }
        // True only when the document's content is what the window shows
        return error == nil && renderTree?.contentWidget != nil
    }
}
