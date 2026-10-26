// Sources/Interop/WebKitLibrary.swift
/*
 WebKitGTK 6.0 (WebKit for GTK 4), found and loaded at run time for WebView, so ActionUI has no build
 or package dependency on it: an app that shows a web page names libwebkitgtk-6.0-4 among its own
 package dependencies, and without the library a WebView shows a placeholder naming that package.
 It is loaded the first time a WebView is made (the library is about 100 MB) and stays loaded for the
 life of the process. Its license (LGPL 2.1, BSD) allows loading it so.

 The library's name carries its API version (6.0, the GTK 4 API) and its ABI version (.so.4, the same
 from WebKitGTK 2.40 to 2.54), and its functions carry no version, so a newer WebKitGTK keeps working
 with no change here. A later ABI version would mean a change in the C interface; the next few are
 tried in case these functions came through it unchanged. Every function used is looked up, and a
 missing one disables WebView as a whole, as a missing library does.

 No WebKit header is used: the C signatures are declared here, from WebKitGTK 2.54's headers. The web
 view is a GtkWidget; WebKit's own types are passed as that widget.
*/

import Glibc
import CAdwaita

@MainActor
final class WebKitLibrary {
    typealias NewView = @convention(c) () -> WidgetPointer?
    typealias LoadURI = @convention(c) (WidgetPointer?, UnsafePointer<CChar>?) -> Void
    typealias LoadHTML = @convention(c) (WidgetPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    typealias Command = @convention(c) (WidgetPointer?) -> Void
    typealias Flag = @convention(c) (WidgetPointer?) -> gboolean
    typealias Text = @convention(c) (WidgetPointer?) -> UnsafePointer<CChar>?
    typealias Number = @convention(c) (WidgetPointer?) -> gdouble

    /// The package that holds the library on Debian and Ubuntu, named to the user when it is missing.
    static let packageName = "libwebkitgtk-6.0-4"

    /// The loaded WebKitGTK, or nil when none was found (or a test disabled it).
    static var shared: WebKitLibrary? {
        if disabledForTesting { return nil }
        if !searched {
            searched = true
            loaded = load()
        }
        return loaded
    }

    /// Tests run WebView without WebKitGTK with this set.
    static var disabledForTesting = false

    private static var searched = false
    private static var loaded: WebKitLibrary?

    /// webkit_web_view_new
    let newView: NewView
    /// webkit_web_view_load_uri, webkit_web_view_load_html (content, base URI)
    let loadURI: LoadURI
    let loadHTML: LoadHTML
    /// webkit_web_view_go_back, _go_forward, _reload, _stop_loading
    let goBack: Command
    let goForward: Command
    let reload: Command
    let stopLoading: Command
    /// webkit_web_view_can_go_back, _can_go_forward, _is_loading
    let canGoBack: Flag
    let canGoForward: Flag
    let isLoading: Flag
    /// webkit_web_view_get_uri, _get_title (owned by the view), _get_estimated_load_progress (0 to 1)
    let uri: Text
    let title: Text
    let progress: Number

    private init?(_ library: UnsafeMutableRawPointer) {
        func function<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: type) }
        }
        guard let newView = function("webkit_web_view_new", as: NewView.self),
              let loadURI = function("webkit_web_view_load_uri", as: LoadURI.self),
              let loadHTML = function("webkit_web_view_load_html", as: LoadHTML.self),
              let goBack = function("webkit_web_view_go_back", as: Command.self),
              let goForward = function("webkit_web_view_go_forward", as: Command.self),
              let reload = function("webkit_web_view_reload", as: Command.self),
              let stopLoading = function("webkit_web_view_stop_loading", as: Command.self),
              let canGoBack = function("webkit_web_view_can_go_back", as: Flag.self),
              let canGoForward = function("webkit_web_view_can_go_forward", as: Flag.self),
              let isLoading = function("webkit_web_view_is_loading", as: Flag.self),
              let uri = function("webkit_web_view_get_uri", as: Text.self),
              let title = function("webkit_web_view_get_title", as: Text.self),
              let progress = function("webkit_web_view_get_estimated_load_progress", as: Number.self) else { return nil }
        self.newView = newView
        self.loadURI = loadURI
        self.loadHTML = loadHTML
        self.goBack = goBack
        self.goForward = goForward
        self.reload = reload
        self.stopLoading = stopLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.uri = uri
        self.title = title
        self.progress = progress
    }

    /// WebKitGTK 6.0 at ABI version 4, else at one of the next few, when it carries every function
    /// used; nil otherwise.
    private static func load() -> WebKitLibrary? {
        for version in 4...7 {
            guard let handle = dlopen("libwebkitgtk-6.0.so.\(version)", RTLD_NOW | RTLD_LOCAL) else { continue }
            if let library = WebKitLibrary(handle) {
                ActionUIModel.shared.logger.log("WebKitGTK 6.0 (libwebkitgtk-6.0.so.\(version)) shows web views", .verbose)
                return library
            }
            // Left loaded: unloading WebKit after its static constructors ran is not safe.
            ActionUIModel.shared.logger.log("libwebkitgtk-6.0.so.\(version) lacks a function ActionUI uses; WebView shows a placeholder", .warning)
            return nil
        }
        ActionUIModel.shared.logger.log("WebKitGTK 6.0 is not installed (package \(packageName)); WebView shows a placeholder", .warning)
        return nil
    }
}
