// Sources/Interop/WebKitLibrary.swift
/*
 WebKitGTK 6.0 (WebKit for GTK 4), found and loaded at run time for WebView, so ActionUI has no build
 or package dependency on it: an app that shows a web page names libwebkitgtk-6.0-4 among its own
 package dependencies, and without the library a WebView shows a placeholder naming that package.
 It is loaded the first time a WebView is made (the library is about 100 MB) and stays loaded for the
 life of the process. Its license (LGPL 2.1, BSD) allows loading it so.

 The library's name carries its API version (6.0, the GTK 4 API) and its ABI version (.so.4, the same
 from WebKitGTK 2.40 to 2.54), and its functions carry no version, so a newer WebKitGTK release keeps
 working with no change here. A later ABI version would mean a change in the C interface; the next few
 are tried in case these functions came through it unchanged. A new API version (WebKitGTK went from
 4.0 to 4.1 for libsoup 3, then to 6.0 for GTK 4) may change a function's arguments, which looking it
 up cannot tell, so only the API versions in apiVersions are loaded: one is added there, with its
 library's ABI version, after the functions declared here are checked against its headers. Every function used is looked up, and a
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
    typealias Object = @convention(c) (WidgetPointer?) -> OpaquePointer?
    typealias SetText = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Void
    typealias SetFlag = @convention(c) (OpaquePointer?, gboolean) -> Void
    typealias NewScript = @convention(c) (UnsafePointer<CChar>?, UInt32, UInt32, UnsafePointer<UnsafePointer<CChar>?>?,
                                          UnsafePointer<UnsafePointer<CChar>?>?) -> OpaquePointer?
    typealias AddScript = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    typealias Release = @convention(c) (OpaquePointer?) -> Void
    typealias NewSession = @convention(c) () -> OpaquePointer?
    typealias TypeOf = @convention(c) () -> GType
    typealias ObjectOf = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias FlagOf = @convention(c) (OpaquePointer?) -> gboolean
    typealias TextOf = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    typealias ViewOf = @convention(c) (OpaquePointer?) -> WidgetPointer?

    /// WebKitPolicyDecisionType: a navigation, a navigation to a new window, a response.
    static let navigationAction: UInt32 = 0, newWindowAction: UInt32 = 1, response: UInt32 = 2
    /// WebKitScriptDialogType: WEBKIT_SCRIPT_DIALOG_BEFORE_UNLOAD_CONFIRM, the "leave this page?" one.
    static let beforeUnloadDialog: UInt32 = 3
    typealias DialogType = @convention(c) (OpaquePointer?) -> UInt32

    /// WebKitUserContentInjectedFrames: WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES, _TOP_FRAME.
    static let allFrames: UInt32 = 0, topFrame: UInt32 = 1
    /// WebKitUserScriptInjectionTime: WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, _END.
    static let documentStart: UInt32 = 0, documentEnd: UInt32 = 1

    /// The API versions whose headers the C signatures here were checked against, newest first, each
    /// with the ABI version its library had then (6.0: WebKitGTK 2.54, libwebkitgtk-6.0.so.4).
    static let apiVersions: [(api: String, abi: Int)] = [("6.0", 4)]

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
    /// webkit_web_view_get_settings (owned by the view), webkit_settings_set_user_agent,
    /// webkit_settings_set_enable_back_forward_navigation_gestures
    let settings: Object
    let setUserAgent: SetText
    let setBackForwardGestures: SetFlag
    /// webkit_web_view_get_user_content_manager (owned by the view), webkit_user_script_new (source,
    /// frames, injection time, allow list, block list), webkit_user_content_manager_add_script (which
    /// keeps the script), webkit_user_script_unref
    let userContentManager: Object
    let newScript: NewScript
    let addScript: AddScript
    let releaseScript: Release
    /// webkit_network_session_new_ephemeral (cookies, cache and storage in memory, for its views
    /// only), webkit_network_session_get_type, webkit_web_view_get_type
    let newEphemeralSession: NewSession
    let networkSessionType: TypeOf
    let webViewType: TypeOf
    /// webkit_navigation_policy_decision_get_navigation_action, webkit_navigation_action_get_request,
    /// webkit_navigation_action_is_user_gesture, webkit_response_policy_decision_get_request,
    /// webkit_response_policy_decision_is_mime_type_supported, webkit_uri_request_get_uri (owned
    /// by the request), webkit_policy_decision_use, _ignore
    let navigationActionOf: ObjectOf
    let actionRequest: ObjectOf
    let isUserGesture: FlagOf
    let responseRequest: ObjectOf
    let showsResponse: FlagOf
    let requestURI: TextOf
    let useDecision: Release
    let ignoreDecision: Release
    /// webkit_permission_request_deny, webkit_web_view_get_network_session (owned by the view),
    /// webkit_download_get_web_view, webkit_download_get_request, webkit_download_cancel
    let denyPermission: Release
    let networkSession: Object
    let downloadView: ViewOf
    let downloadRequest: ObjectOf
    let cancelDownload: Release
    /// webkit_script_dialog_get_dialog_type, webkit_script_dialog_confirm_set_confirmed,
    /// webkit_authentication_request_cancel, webkit_settings_set_enable_fullscreen
    let dialogType: DialogType
    let setConfirmed: SetFlag
    let cancelAuthentication: Release
    let setFullscreenEnabled: SetFlag

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
              let progress = function("webkit_web_view_get_estimated_load_progress", as: Number.self),
              let settings = function("webkit_web_view_get_settings", as: Object.self),
              let setUserAgent = function("webkit_settings_set_user_agent", as: SetText.self),
              let setBackForwardGestures = function("webkit_settings_set_enable_back_forward_navigation_gestures", as: SetFlag.self),
              let userContentManager = function("webkit_web_view_get_user_content_manager", as: Object.self),
              let newScript = function("webkit_user_script_new", as: NewScript.self),
              let addScript = function("webkit_user_content_manager_add_script", as: AddScript.self),
              let releaseScript = function("webkit_user_script_unref", as: Release.self),
              let newEphemeralSession = function("webkit_network_session_new_ephemeral", as: NewSession.self),
              let networkSessionType = function("webkit_network_session_get_type", as: TypeOf.self),
              let webViewType = function("webkit_web_view_get_type", as: TypeOf.self),
              let navigationActionOf = function("webkit_navigation_policy_decision_get_navigation_action", as: ObjectOf.self),
              let actionRequest = function("webkit_navigation_action_get_request", as: ObjectOf.self),
              let isUserGesture = function("webkit_navigation_action_is_user_gesture", as: FlagOf.self),
              let responseRequest = function("webkit_response_policy_decision_get_request", as: ObjectOf.self),
              let showsResponse = function("webkit_response_policy_decision_is_mime_type_supported", as: FlagOf.self),
              let requestURI = function("webkit_uri_request_get_uri", as: TextOf.self),
              let useDecision = function("webkit_policy_decision_use", as: Release.self),
              let ignoreDecision = function("webkit_policy_decision_ignore", as: Release.self),
              let denyPermission = function("webkit_permission_request_deny", as: Release.self),
              let networkSession = function("webkit_web_view_get_network_session", as: Object.self),
              let downloadView = function("webkit_download_get_web_view", as: ViewOf.self),
              let downloadRequest = function("webkit_download_get_request", as: ObjectOf.self),
              let cancelDownload = function("webkit_download_cancel", as: Release.self),
              let dialogType = function("webkit_script_dialog_get_dialog_type", as: DialogType.self),
              let setConfirmed = function("webkit_script_dialog_confirm_set_confirmed", as: SetFlag.self),
              let cancelAuthentication = function("webkit_authentication_request_cancel", as: Release.self),
              let setFullscreenEnabled = function("webkit_settings_set_enable_fullscreen", as: SetFlag.self) else { return nil }
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
        self.settings = settings
        self.setUserAgent = setUserAgent
        self.setBackForwardGestures = setBackForwardGestures
        self.userContentManager = userContentManager
        self.newScript = newScript
        self.addScript = addScript
        self.releaseScript = releaseScript
        self.newEphemeralSession = newEphemeralSession
        self.networkSessionType = networkSessionType
        self.webViewType = webViewType
        self.navigationActionOf = navigationActionOf
        self.actionRequest = actionRequest
        self.isUserGesture = isUserGesture
        self.responseRequest = responseRequest
        self.showsResponse = showsResponse
        self.requestURI = requestURI
        self.useDecision = useDecision
        self.ignoreDecision = ignoreDecision
        self.denyPermission = denyPermission
        self.networkSession = networkSession
        self.downloadView = downloadView
        self.downloadRequest = downloadRequest
        self.cancelDownload = cancelDownload
        self.dialogType = dialogType
        self.setConfirmed = setConfirmed
        self.cancelAuthentication = cancelAuthentication
        self.setFullscreenEnabled = setFullscreenEnabled
    }

    /// The address a request names (a navigation action's, a response's, a download's), "" if none.
    func address(ofRequest request: OpaquePointer?) -> String {
        request.flatMap { requestURI($0) }.map { String(cString: $0) } ?? ""
    }

    /// A web view of its own ephemeral network session: its cookies, cache and web storage are in
    /// memory and shared with no other view (webkit_web_view_new's views share the default
    /// session, kept on disk). Floating, as webkit_web_view_new's; nil when it could not be made.
    func newPrivateView() -> WidgetPointer? {
        guard let session = newEphemeralSession() else { return nil }
        // The view keeps its own reference.
        defer { g_object_unref(UnsafeMutableRawPointer(session)) }
        var value = GValue()
        g_value_init(&value, networkSessionType())
        defer { g_value_unset(&value) }
        g_value_set_object(&value, UnsafeMutableRawPointer(session))
        let object: UnsafeMutablePointer<GObject>? = "network-session".withCString { name in
            var names: [UnsafePointer<CChar>?] = [name]
            return names.withUnsafeMutableBufferPointer { g_object_new_with_properties(webViewType(), 1, $0.baseAddress, &value) }
        }
        return object.map { WidgetPointer(OpaquePointer($0)) }
    }

    /// The first library found, by API version (apiVersions) and then ABI version (the one checked, then
    /// the next few), when it carries every function used; nil otherwise.
    private static func load() -> WebKitLibrary? {
        for (api, checked) in apiVersions {
            for abi in checked...(checked + 3) {
                let name = "libwebkitgtk-\(api).so.\(abi)"
                guard let handle = dlopen(name, RTLD_NOW | RTLD_LOCAL) else { continue }
                if let library = WebKitLibrary(handle) {
                    ActionUIModel.shared.logger.log("WebKitGTK \(api) (\(name)) shows web views", .verbose)
                    return library
                }
                // Left loaded, and no other tried: unloading WebKit after its static constructors ran is
                // not safe, nor is loading a second WebKit beside it.
                ActionUIModel.shared.logger.log("\(name) lacks a function ActionUI uses; WebView shows a placeholder", .warning)
                return nil
            }
        }
        ActionUIModel.shared.logger.log("WebKitGTK \(apiVersions.map(\.api).joined(separator: " or ")) is not installed (package \(packageName)); WebView shows a placeholder", .warning)
        return nil
    }
}
