// Sources/Runtime/AppPanels.swift
/*
 The application's standalone alert and its file panels, behind the synchronous C calls
 actionUIAppRunAlert, actionUIAppRunOpenPanel and actionUIAppRunSavePanel: an AdwAlertDialog and a
 GtkFileDialog. Each call returns once the user answers. Until then a nested GLib main loop keeps
 the application running underneath, as NSAlert.runModal and NSOpenPanel.runModal do on macOS:
 windows redraw and handlers run. The work of DispatchQueue.main waits when the call itself came
 through it (a call from another thread), as a serial queue does on macOS.

 The configuration is the macOS JSON, read key by key (a key of the wrong type is ignored):
 - Alert: title, message, style, buttons (the first is the default, shown rightmost; a button
   titled "Cancel" answers Escape, as in AppKit, and so does a single button). libadwaita alerts
   have no style icon, so style is ignored.
 - File panels: title, prompt (the accept button), directoryURL, nameFieldStringValue (save),
   allowedContentTypes (filename extensions, MIME types, or the common uniform type identifiers),
   allowsMultipleSelection, canChooseFiles, canChooseDirectories, allowsOtherFileTypes. GTK chooses
   files or folders, not both, so an open panel that allows both chooses files. message,
   identifier, showsHiddenFiles, treatsFilePackagesAsDirectories and canCreateDirectories have no
   counterpart in GtkFileDialog (which may be the desktop portal's chooser) and are ignored.

 The panels are parented to the active window, modal to it; with no window the alert is a window
 of its own. Called before the application runs (GTK is not set up yet) they log why and return
 nil.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

// MARK: - The requests, read from the JSON

/// An alert as the JSON describes it, with the buttons in libadwaita's terms.
struct AlertRequest: Equatable {
    var heading: String?
    var body: String?
    /// Button titles in the JSON's order; the first is the default.
    var buttons: [String]
    /// The button Escape answers, or nil when Escape does nothing.
    var closeButton: Int?

    init(json: String?) {
        let config = AppPanels.dictionary(json)
        heading = config["title"] as? String
        body = config["message"] as? String
        let titles = config["buttons"] as? [String] ?? []
        buttons = titles.isEmpty ? ["OK"] : titles
        if let cancel = buttons.firstIndex(of: "Cancel") {
            closeButton = cancel
        } else {
            closeButton = buttons.count == 1 ? 0 : nil
        }
    }

    /// The order the buttons are added in, which libadwaita shows from left to right: the JSON's
    /// last first, so its first (the default) is rightmost, where AppKit puts it too.
    var displayOrder: [Int] { Array(buttons.indices.reversed()) }

    static func responseID(_ index: Int) -> String { "button-\(index)" }

    /// The button a response ID names.
    func button(response: String?) -> String? {
        guard let response, response.hasPrefix("button-"), let index = Int(response.dropFirst("button-".count)),
              buttons.indices.contains(index) else { return nil }
        return buttons[index]
    }
}

/// A file panel as the JSON describes it, in GtkFileDialog's terms.
struct FilePanelRequest: Equatable {
    enum Mode: Equatable {
        case openFile, openFiles, selectFolder, selectFolders, save
    }

    /// One allowed type: a filename extension or a MIME type pattern.
    enum FileType: Equatable {
        case suffix(String)
        case mimeType(String)
    }

    var mode: Mode
    var title: String?
    var acceptLabel: String?
    var initialFolder: String?
    var initialName: String?
    /// Empty: any file.
    var types: [FileType]
    var allowsOtherTypes: Bool

    init(json: String?, saving: Bool) {
        let config = AppPanels.dictionary(json)
        title = config["title"] as? String
        acceptLabel = config["prompt"] as? String
        initialFolder = (config["directoryURL"] as? String).map(Self.path(directoryURL:))
        initialName = saving ? config["nameFieldStringValue"] as? String : nil
        allowsOtherTypes = config["allowsOtherFileTypes"] as? Bool ?? false
        types = (config["allowedContentTypes"] as? [String] ?? []).flatMap(Self.fileTypes)
        if saving {
            mode = .save
        } else {
            let multiple = config["allowsMultipleSelection"] as? Bool ?? false
            let files = config["canChooseFiles"] as? Bool ?? true
            let folders = config["canChooseDirectories"] as? Bool ?? false
            if folders && !files {
                mode = multiple ? .selectFolders : .selectFolder
            } else {
                mode = multiple ? .openFiles : .openFile
            }
        }
    }

    /// macOS reads directoryURL as a path; a file URL is taken too.
    static func path(directoryURL: String) -> String {
        guard directoryURL.hasPrefix("file://"), let url = URL(string: directoryURL) else { return directoryURL }
        return url.path
    }

    /// What one allowedContentTypes entry allows: an extension ("json"), a MIME type ("image/png",
    /// "image/*"), or a uniform type identifier ("public.image") GTK knows by its MIME types. An
    /// identifier of no particular type ("public.data", "public.item") allows nothing more
    /// specific than any file; an unknown one, nothing.
    static func fileTypes(_ entry: String) -> [FileType] {
        if entry.contains("/") {
            return [.mimeType(entry)]
        }
        if !entry.contains(".") {
            return entry.isEmpty ? [] : [.suffix(entry)]
        }
        if let mimeTypes = mimeTypesForIdentifier[entry] {
            return mimeTypes.map(FileType.mimeType)
        }
        return []
    }

    /// The common uniform type identifiers, by their MIME types.
    static let mimeTypesForIdentifier: [String: [String]] = [
        "public.data": ["application/octet-stream", "*/*"],
        "public.item": ["*/*"],
        "public.content": ["*/*"],
        "public.image": ["image/*"],
        "public.jpeg": ["image/jpeg"],
        "public.png": ["image/png"],
        "public.tiff": ["image/tiff"],
        "public.heic": ["image/heic"],
        "com.compuserve.gif": ["image/gif"],
        "org.webmproject.webp": ["image/webp"],
        "com.microsoft.bmp": ["image/bmp"],
        "public.svg-image": ["image/svg+xml"],
        "public.text": ["text/*"],
        "public.plain-text": ["text/plain"],
        "public.utf8-plain-text": ["text/plain"],
        "public.json": ["application/json"],
        "public.xml": ["application/xml", "text/xml"],
        "public.html": ["text/html"],
        "public.comma-separated-values-text": ["text/csv"],
        "public.python-script": ["text/x-python", "text/x-python3"],
        "com.adobe.pdf": ["application/pdf"],
        "public.audio": ["audio/*"],
        "public.movie": ["video/*"],
        "public.video": ["video/*"],
        "public.mpeg-4": ["video/mp4"],
        "public.zip-archive": ["application/zip"],
    ]

    /// The allowed extensions, in order.
    var suffixes: [String] {
        types.compactMap { if case .suffix(let suffix) = $0 { suffix } else { nil } }
    }

    /// Whether the types restrict the choice at all ("*/*" does not).
    var restrictsTypes: Bool {
        !types.isEmpty && !types.contains(.mimeType("*/*"))
    }

    /// The saved path with the first allowed extension added when it has none of them, as
    /// NSSavePanel does; unchanged when other types are allowed or the types are not extensions.
    func savedPath(_ path: String) -> String {
        guard mode == .save, !allowsOtherTypes, let first = suffixes.first else { return path }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let lowered = name.lowercased()
        if suffixes.contains(where: { lowered.hasSuffix("." + $0.lowercased()) }) {
            return path
        }
        return path + "." + first
    }
}

// MARK: - Running them

/// What a nested main loop waits for.
@MainActor
private final class NestedAnswer<T> {
    var value: T?
    var answered = false
}

@MainActor
public enum AppPanels {
    /// actionUIAppRunAlert: the chosen button's title.
    public static func runAlert(json: String?) -> String? {
        runAlert(AlertRequest(json: json))
    }

    /// actionUIAppRunOpenPanel: the chosen paths.
    public static func runOpenPanel(json: String?) -> [String]? {
        runFilePanel(FilePanelRequest(json: json, saving: false))
    }

    /// actionUIAppRunSavePanel: the chosen path.
    public static func runSavePanel(json: String?) -> String? {
        runFilePanel(FilePanelRequest(json: json, saving: true))?.first
    }

    /// The JSON's top-level object; empty for nil or anything else.
    nonisolated static func dictionary(_ json: String?) -> [String: Any] {
        guard let json, let parsed = try? ActionUIJSON.value(from: json) as? [String: Any] else { return [:] }
        return parsed
    }

    /// The cancellables of the calls waiting for an answer, innermost last.
    private static var open: [UnsafeMutablePointer<GCancellable>] = []

    /// Cancels every call still waiting for an answer, so each returns nil: the application is
    /// terminating, which on macOS ends the process with the panel up.
    static func cancelAll() {
        for cancellable in open {
            g_cancellable_cancel(cancellable)
        }
    }

    /// Makes a call's cancellable, known to cancelAll until the call returns (closeCancellable).
    private static func openCancellable() -> UnsafeMutablePointer<GCancellable> {
        let cancellable = g_cancellable_new()!
        open.append(cancellable)
        return cancellable
    }

    private static func closeCancellable(_ cancellable: UnsafeMutablePointer<GCancellable>) {
        open.removeAll { $0 == cancellable }
        g_object_unref(UnsafeMutableRawPointer(cancellable))
    }

    /// Called with each dialog as it is presented (the AdwAlertDialog or the GtkFileDialog) and
    /// the cancellable of its call, so a test can answer or cancel it.
    static var presentedForTesting: ((OpaquePointer, UnsafeMutablePointer<GCancellable>) -> Void)?

    /// Runs the default main context until `finish` is called. The completion handed to `start`
    /// is that `finish`; `start` begins the asynchronous call.
    private static func runNested<T>(_ start: (_ finish: @escaping @MainActor (T?) -> Void) -> Void) -> T? {
        let answer = NestedAnswer<T>()
        let loop = g_main_loop_new(nil, 0)!
        defer { g_main_loop_unref(loop) }
        start { value in
            answer.value = value
            answer.answered = true
            g_main_loop_quit(loop)
        }
        if !answer.answered {
            g_main_loop_run(loop)
        }
        return answer.value
    }

    private static func refusedBeforeRun(_ function: String) -> Bool {
        guard !AdwaitaApplication.shared.hasStarted else { return false }
        ActionUIModel.shared.logger.log("\(function): call it while the application runs (from didFinishLaunching on)", .error)
        return true
    }

    /// The title of the button the user chose, or nil: closed without a button, which only a
    /// cancellation does (the application terminating, or the parent window going away).
    static func runAlert(_ request: AlertRequest) -> String? {
        guard !refusedBeforeRun("actionUIAppRunAlert") else { return nil }
        let widget = OwnedObject(retaining: UnsafeMutableRawPointer(adw_alert_dialog_new(request.heading, request.body)!))
        let alert: UnsafeMutablePointer<AdwAlertDialog> = widget.typed()
        for index in request.displayOrder {
            adw_alert_dialog_add_response(alert, AlertRequest.responseID(index), request.buttons[index])
        }
        // The default button looks suggested, unless it is the cancel button (GNOME never
        // suggests canceling); it is the default either way, as in AppKit.
        if request.closeButton != 0 || request.buttons.count == 1 {
            adw_alert_dialog_set_response_appearance(alert, AlertRequest.responseID(0), ADW_RESPONSE_SUGGESTED)
        }
        adw_alert_dialog_set_default_response(alert, AlertRequest.responseID(0))
        if let close = request.closeButton {
            adw_alert_dialog_set_close_response(alert, AlertRequest.responseID(close))
        } else {
            adw_dialog_set_can_close(typed(alert), 0)
        }
        let parent = AdwaitaApplication.shared.activeWindow().map { UnsafeMutablePointer<GtkWidget>(OpaquePointer($0)) }
        let cancellable = openCancellable()
        defer { closeCancellable(cancellable) }
        // A parent window taken off screen under the alert (destroyed when another window is
        // presented under its UUID) takes the alert with it, unanswered: the call is canceled then,
        // on "unmap", while the alert is still presented ("destroy" comes after, and libadwaita
        // complains). The window may be gone by the end; a reference would keep it from going,
        // so a weak pointer tells whether its handler is still there to disconnect.
        let watchedParent = UnsafeMutablePointer<gpointer?>.allocate(capacity: 1)
        watchedParent.initialize(to: parent.map { UnsafeMutableRawPointer($0) })
        var unmapHandler: gulong = 0
        if let window = watchedParent.pointee {
            g_object_add_weak_pointer(window.assumingMemoryBound(to: GObject.self), watchedParent)
            unmapHandler = connectSignal(window, "unmap", .instanceOnly) { g_cancellable_cancel(cancellable) }
        }
        defer {
            if let window = watchedParent.pointee {
                if g_signal_handler_is_connected(window, unmapHandler) != 0 {
                    g_signal_handler_disconnect(window, unmapHandler)
                }
                g_object_remove_weak_pointer(window.assumingMemoryBound(to: GObject.self), watchedParent)
            }
            watchedParent.deallocate()
        }
        let response: String? = runNested { finish in
            let run: ReadyRun = { result in
                finish(swiftString(adw_alert_dialog_choose_finish(alert, result)))
            }
            let data = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
            adw_alert_dialog_choose(alert, parent, cancellable, readyTrampoline, data)
            presentedForTesting?(OpaquePointer(alert), cancellable)
        }
        return request.button(response: response)
    }

    /// The chosen paths, or nil when the panel was canceled.
    static func runFilePanel(_ request: FilePanelRequest) -> [String]? {
        let function = request.mode == .save ? "actionUIAppRunSavePanel" : "actionUIAppRunOpenPanel"
        guard !refusedBeforeRun(function) else { return nil }
        let dialog = gtk_file_dialog_new()!
        defer { g_object_unref(UnsafeMutableRawPointer(dialog)) }
        if let title = request.title {
            gtk_file_dialog_set_title(dialog, title)
        }
        if let label = request.acceptLabel {
            gtk_file_dialog_set_accept_label(dialog, label)
        }
        if let folder = request.initialFolder {
            let file = g_file_new_for_path(folder)!
            gtk_file_dialog_set_initial_folder(dialog, file)
            g_object_unref(UnsafeMutableRawPointer(file))
        }
        if let name = request.initialName {
            gtk_file_dialog_set_initial_name(dialog, name)
        }
        if request.restrictsTypes {
            applyFilters(request, to: dialog)
        }
        let parent = AdwaitaApplication.shared.activeWindow()
        let cancellable = openCancellable()
        defer { closeCancellable(cancellable) }
        let paths: [String]? = runNested { finish in
            let run: ReadyRun = { result in
                finish(finishFilePanel(dialog, request.mode, result))
            }
            let data = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
            switch request.mode {
            case .openFile: gtk_file_dialog_open(dialog, parent, cancellable, readyTrampoline, data)
            case .openFiles: gtk_file_dialog_open_multiple(dialog, parent, cancellable, readyTrampoline, data)
            case .selectFolder: gtk_file_dialog_select_folder(dialog, parent, cancellable, readyTrampoline, data)
            case .selectFolders: gtk_file_dialog_select_multiple_folders(dialog, parent, cancellable, readyTrampoline, data)
            case .save: gtk_file_dialog_save(dialog, parent, cancellable, readyTrampoline, data)
            }
            presentedForTesting?(dialog, cancellable)
        }
        guard let paths, !paths.isEmpty else { return nil }
        return request.mode == .save ? paths.map(request.savedPath) : paths
    }

    /// One filter with every allowed type, the default; and, for a save panel that allows other
    /// types (the only panel macOS applies that key to), one for any file.
    private static func applyFilters(_ request: FilePanelRequest, to dialog: OpaquePointer) {
        let filters = g_list_store_new(gtk_file_filter_get_type())!
        defer { g_object_unref(UnsafeMutableRawPointer(filters)) }
        let allowed = gtk_file_filter_new()!
        defer { g_object_unref(UnsafeMutableRawPointer(allowed)) }
        var names: [String] = []
        for type in request.types {
            switch type {
            case .suffix(let suffix):
                gtk_file_filter_add_suffix(allowed, suffix)
                names.append(suffix)
            case .mimeType(let mimeType):
                gtk_file_filter_add_mime_type(allowed, mimeType)
                names.append(mimeType)
            }
        }
        gtk_file_filter_set_name(allowed, names.joined(separator: ", "))
        g_list_store_append(filters, UnsafeMutableRawPointer(allowed))
        if request.mode == .save && request.allowsOtherTypes {
            let any = gtk_file_filter_new()!
            gtk_file_filter_add_pattern(any, "*")
            gtk_file_filter_set_name(any, "All Files")
            g_list_store_append(filters, UnsafeMutableRawPointer(any))
            g_object_unref(UnsafeMutableRawPointer(any))
        }
        gtk_file_dialog_set_filters(dialog, filters)
        gtk_file_dialog_set_default_filter(dialog, allowed)
    }

    /// The paths of the chosen files; nil when the dialog was dismissed or failed. A chosen file
    /// with no local path (a remote location the portal offers) is left out.
    private static func finishFilePanel(_ dialog: OpaquePointer, _ mode: FilePanelRequest.Mode, _ result: OpaquePointer?) -> [String]? {
        var error: UnsafeMutablePointer<GError>?
        defer { if let error { g_error_free(error) } }
        switch mode {
        case .openFile, .selectFolder, .save:
            let file: OpaquePointer?
            switch mode {
            case .openFile: file = gtk_file_dialog_open_finish(dialog, result, &error)
            case .selectFolder: file = gtk_file_dialog_select_folder_finish(dialog, result, &error)
            default: file = gtk_file_dialog_save_finish(dialog, result, &error)
            }
            guard let file else { return nil }
            defer { g_object_unref(UnsafeMutableRawPointer(file)) }
            return localPath(file).map { [$0] }
        case .openFiles, .selectFolders:
            let model = mode == .openFiles
                ? gtk_file_dialog_open_multiple_finish(dialog, result, &error)
                : gtk_file_dialog_select_multiple_folders_finish(dialog, result, &error)
            guard let model else { return nil }
            defer { g_object_unref(UnsafeMutableRawPointer(model)) }
            var paths: [String] = []
            for index in 0..<g_list_model_get_n_items(model) {
                guard let item = g_list_model_get_item(model, index) else { continue }
                if let path = localPath(OpaquePointer(item)) {
                    paths.append(path)
                }
                g_object_unref(item)
            }
            return paths
        }
    }

    private static func localPath(_ file: OpaquePointer) -> String? {
        guard let path = g_file_get_path(file) else { return nil }
        defer { g_free(path) }
        return String(cString: path)
    }
}
