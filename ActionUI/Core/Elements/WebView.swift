// Core/Elements/WebView.swift
/*
 Sample JSON for WebView:
 {
   "type": "WebView",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://www.swift.org",          // Optional: Initial URL to load; takes precedence over html
     "html": "<h1>Hello</h1>",               // Optional: Inline HTML to render (used when url is absent)
     "baseURL": "https://example.com",        // Optional: Base URL for resolving relative links in html content
     "customUserAgent": "MyApp/1.0",          // Optional: Overrides the default WebKit user agent
     "backForwardNavigationGestures": true,   // Optional: Bool, enable swipe back/forward gestures; default true
     "magnificationGestures": true,           // Optional: Bool, enable pinch-to-zoom; default true
     "linkPreviews": true,                    // Optional: Bool, enable long-press link previews; default true
     "limitsNavigationsToAppBoundDomains": false, // Optional: Bool; restrict navigation to app-bound domains; default false
     "upgradeKnownHostsToHTTPS": false,           // Optional: Bool; auto-upgrade known HTTP hosts to HTTPS; default false
     "userScripts": [     // Optional: Array of JS descriptors injected before/after page load
       {
         "injectionTime": "documentStart", // Required: "documentStart" or "documentEnd"
         "source": "window.myFlag = true;", // One required source — inline JS string
         // OR "filePath": "/absolute/path/to/script.js"  — absolute path to a .js file on disk
         // OR "resourceName": "MyScript.js"              — .js file in the app's main bundle
         "forMainFrameOnly": false          // Optional Bool; inject into all frames when false; default false
       }
     ],
     "valueChangeActionID": "onURLChange",    // Optional: Fired when URL changes after a navigation completes
     "navigationActionID": "onNavigation"     // Optional: Fired when isLoading changes (navigation started / finished)
   }
 }

 Note: Two backings exist and are selected globally by the host app via
   ActionUIRegistry.shared.webViewImplementation:
     .native  (default) – a UIKit/AppKit WKWebView wrapped in NS/UIViewRepresentable.
                          Works on the package baseline (macOS 14.6+ / iOS 17.6+).
     .swiftUI            – SwiftUI's WebKit.WebView. Requires iOS 26.0+ / macOS 26.0+;
                          on older OS versions it falls back to the native backing.
   Both backings expose the identical observable surface and honour the same properties.

 Note: userScripts are injected via WKUserScript on each page load.
 The "resourceName" lookup strips a trailing .js extension then calls Bundle.main.path(forResource:ofType:),
 mirroring Image.swift's resourceName pattern.

 Observable state (via getElementValue / getElementState):
   value (String)                     Current page URL.
                                      Write a URL string to navigate, or one of these commands:
                                        "#goBack"    – navigate back  (no-op if canGoBack is false)
                                        "#goForward" – navigate forward (no-op if canGoForward is false)
                                        "#reload"    – reload the current page
                                        "#stop"      – cancel an in-flight load
   states["title"]     String?        Page <title> text; absent until first load completes
   states["isLoading"] Bool           true while a navigation is in flight
   states["estimatedProgress"] Double 0.0–1.0 load progress
   states["canGoBack"] Bool           Back list has items
   states["canGoForward"] Bool        Forward list has items

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
 */

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension WebView {
    /// WebView's properties, parsed from the raw dictionary. Built at the start of every render.
    /// Both backings (WebViewContent in WebView+SwiftUI.swift and WKWebViewRepresentable in WebViewNative.swift) read this.
    struct Props: Sendable {
        enum InjectionTime: String, Sendable, CaseIterable {
            case documentStart, documentEnd
        }

        struct UserScript: Sendable {
            var source: String?
            var filePath: String?
            var resourceName: String?
            /// documentEnd when absent or not a valid name.
            var injectionTime = InjectionTime.documentEnd
            var forMainFrameOnly = false

            init(_ descriptor: [String: Any]) {
                source = descriptor["source"] as? String
                filePath = descriptor["filePath"] as? String
                resourceName = descriptor["resourceName"] as? String
                injectionTime = (descriptor["injectionTime"] as? String).flatMap(InjectionTime.init(rawValue:)) ?? .documentEnd
                forMainFrameOnly = descriptor["forMainFrameOnly"] as? Bool ?? false
            }
        }

        var url: String?
        var html: String?
        var baseURL: String?
        var customUserAgent: String?
        var backForwardNavigationGestures = true
        var magnificationGestures = true
        var linkPreviews = true
        /// nil leaves the web view's own default.
        var limitsNavigationsToAppBoundDomains: Bool?
        var upgradeKnownHostsToHTTPS: Bool?
        /// The scripts with a source, a file path or a resource name; others are skipped.
        var userScripts: [UserScript] = []
        var valueChangeActionID: String?
        var navigationActionID: String?

        init(_ properties: [String: Any]) {
            url = properties["url"] as? String
            html = properties["html"] as? String
            baseURL = properties["baseURL"] as? String
            customUserAgent = properties["customUserAgent"] as? String
            backForwardNavigationGestures = properties["backForwardNavigationGestures"] as? Bool ?? true
            magnificationGestures = properties["magnificationGestures"] as? Bool ?? true
            linkPreviews = properties["linkPreviews"] as? Bool ?? true
            limitsNavigationsToAppBoundDomains = properties["limitsNavigationsToAppBoundDomains"] as? Bool
            upgradeKnownHostsToHTTPS = properties["upgradeKnownHostsToHTTPS"] as? Bool
            userScripts = (properties["userScripts"] as? [[String: Any]] ?? []).map(UserScript.init).filter {
                $0.source != nil || $0.filePath != nil || $0.resourceName != nil
            }
            valueChangeActionID = properties["valueChangeActionID"] as? String
            navigationActionID = properties["navigationActionID"] as? String
        }
    }
}

struct WebView: ActionUIElementSpec {
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let existing = model.value as? String { return existing }
        return Props(model.properties).url ?? ""
    }

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states.isEmpty {
            states["isLoading"] = false
            states["estimatedProgress"] = 0.0
            states["canGoBack"] = false
            states["canGoForward"] = false
        }
        return states
    }
}
