// Core/Common/DocumentLoader.swift
/*
 Loading a description into a window, without the views: where a LoadableView's text points (a
 remote URL, a file, a bundled resource), the format of a file or URL, loading the data as the
 window's content or as a sub-view of a LoadableView, and firing a LoadableView's viewDidLoadActionID
 once per source. Where loaded content came from and how far it is trusted (JSONContentOrigin): the
 app's own resources and the host are trusted; a remote document, or a local file outside the
 resources, is less trusted, and so is everything a less-trusted document loads in turn.

 (The SwiftUI views are FileLoadableView and RemoteLoadableView, in Common/.)
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Where a part of a window's content came from, and how far it is trusted: kept on the view model
/// of each element it loaded (ActionUIModel.origin(windowUUID:viewID:) reads it). Content the host
/// passed in itself (loadDescription, presentModal, insertElement) is `host`. One object is shared
/// by all the elements of one load, so a view model holds a single reference.
public final class JSONContentOrigin: Sendable, Equatable, CustomStringConvertible {
    public enum Source: Sendable, Equatable {
        /// JSON or data the host passed in itself.
        case host
        /// A file in the app's own resources (bundle or resource folder), by its resolved path.
        case resource(String)
        /// A local file anywhere else, by its resolved path.
        case file(String)
        /// An http or https address.
        case remote(URL)
    }

    public enum Trust: Int, Sendable, Comparable {
        case lessTrusted = 0
        case trusted = 1

        public static func < (lhs: Trust, rhs: Trust) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let source: Source
    /// The lower of the source's own trust and that of the content around it.
    public let trust: Trust
    /// The LoadableView (its element id) this content was loaded into; nil for a window's root.
    public let parentID: Int?

    public init(source: Source, trust: Trust, parentID: Int?) {
        self.source = source
        self.trust = trust
        self.parentID = parentID
    }

    /// The host's own content.
    public static let host = JSONContentOrigin(source: .host, trust: .trusted, parentID: nil)

    public static func == (lhs: JSONContentOrigin, rhs: JSONContentOrigin) -> Bool {
        lhs.source == rhs.source && lhs.trust == rhs.trust && lhs.parentID == rhs.parentID
    }

    public var description: String {
        let source: String
        switch self.source {
        case .host: source = "host"
        case .resource(let path): source = "resource \(path)"
        case .file(let path): source = "file \(path)"
        case .remote(let url): source = "remote \(url.absoluteString)"
        }
        return "\(source), \(trust == .trusted ? "trusted" : "less trusted")" + (parentID.map { ", in LoadableView \($0)" } ?? "")
    }
}

/// At most `loads` LoadableView loads per window in any `seconds` (ActionUIConfiguration.limits.loadBudget).
public struct ActionUILoadBudget: Sendable, Equatable {
    public var loads: Int
    public var seconds: Double

    public init(loads: Int, seconds: Double) {
        self.loads = loads
        self.seconds = seconds
    }
}

/// Something a part of a window's content may do, which the trust policy is asked about
/// (ActionUIModel.allows). The renderers ask before each, menuCommands aside (see there).
public enum ActionUICapability: Sendable, Equatable {
    /// A LoadableView loading this source, asked with the origin of the content the LoadableView is
    /// in, before anything is read, and again about the address a redirect reaches, before the
    /// content is loaded (the load budget and size caps apply whatever the answer).
    case load(JSONContentOrigin.Source)
    /// Opening an address: a Link, or openURL.
    case openLink(URL)
    /// A WebView showing this address; nil for inline html.
    case webView(URL?)
    /// The base address a WebView's inline html runs under (its origin, for cookies and storage).
    case webViewBaseURL(URL)
    /// A WebView running the user scripts its content gives (its userScripts property, inline or
    /// from files; each file is also asked about, webViewScriptFile). Asked when the WebView is
    /// made, only when it has scripts; refused, it runs none of them.
    case webViewUserScripts
    /// A WebView keeping its cookies, cache and web storage in the app's persistent data store,
    /// shared with the app's other WebViews. Asked when the WebView is made; refused, it gets a
    /// private store of its own that lasts as long as the WebView. Apple and Linux; an Android
    /// WebView has the app's one store and does not ask.
    case webViewPersistentData
    /// A WebView user script read from this file.
    case webViewScriptFile(String)
    /// An Image, Canvas image, VideoPlayer, AsyncImage or ShareLink reading this local file.
    case readLocalFile(String)
    /// Setting the window's title (navigationTitle on a window root, a WindowGroup title).
    case windowTitle
    /// Presenting a sheet, full-screen cover, popover, alert or confirmation dialog.
    case presentModal
    /// Adding menu commands (CommandMenu, CommandGroup). Not asked today: menu commands come only
    /// from the host and from the app's own resources (a WindowGroup scene on Apple, a WindowGroup
    /// file in the resource folder on Linux), never from content loaded at run time.
    case menuCommands
    /// Firing this action, asked with the origin of the element that fires it (the host's for a
    /// menu bar item, a toast's or a dialog's button) before the host's handler runs.
    case action(String)
}

/// The host's say over how far content is trusted and what it may do,
/// set on ActionUIModel.shared.trustPolicy before loading. One object serves every window; a host
/// that wants rules per window switches on the origin's parentID or keeps its own map.
public protocol ActionUITrustPolicy: Sendable {
    /// The trust of content loaded from `source` inside content of origin `parent` (nil only for a
    /// window's root; a LoadableView in a template row has its row's content as parent, and one
    /// whose surroundings cannot be told a less-trusted parent), given what ActionUI decides
    /// `byDefault`. The default implementation keeps that. Judge a parent by its `trust`: the
    /// less-trusted parent of unknown surroundings has the source `.host`.
    @MainActor func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?,
                          byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust
    /// Whether content of `origin` may do `capability`. The default implementation is
    /// DefaultTrustPolicy's.
    @MainActor func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool
}

extension ActionUITrustPolicy {
    @MainActor public func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?,
                                 byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust {
        byDefault
    }

    @MainActor public func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        DefaultTrustPolicy.allowsByDefault(capability, for: origin)
    }
}

/// ActionUI's own policy: trust as classified, and the default refusals for less-trusted content.
public struct DefaultTrustPolicy: ActionUITrustPolicy {
    public init() {}

    /// The schemes a less-trusted link may open.
    public static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    /// The schemes a less-trusted WebView may show.
    public static let webViewSchemes: Set<String> = ["http", "https"]

    /// Whether the file at `path` is inside one of the app's resource folders (symbolic links
    /// followed), the folders whose documents are trusted.
    @MainActor
    public static func isInAppResources(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return ActionUIRendererHooks.resourceFolders().contains { ActionUIResourceFolder.isFile(url, inside: $0) }
    }

    /// Whether two addresses have the same origin: scheme, host and port (the scheme's default
    /// port when none is written).
    public static func haveSameOrigin(_ first: URL, _ second: URL) -> Bool {
        func origin(_ url: URL) -> (String, String, Int?)? {
            guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : nil)
            return (scheme, host, port)
        }
        guard let a = origin(first), let b = origin(second) else { return false }
        return a == b
    }

    /// What content of `origin` may do when the host does not say: trusted content anything; less
    /// trusted content may open only web and mail links (linkSchemes), show only web addresses in a
    /// WebView (webViewSchemes), give its inline html a base address only of its own document's
    /// origin, run no WebView user scripts, keep no WebView data in the app's persistent store,
    /// read local files (images, videos, WebView script files) and load ActionUI JSON from local
    /// files only inside the app's resources, and neither set the window's title nor present its
    /// own sheets, covers and popovers; for now it may do anything else (each further refusal
    /// comes with the renderer change that enforces it).
    @MainActor
    public static func allowsByDefault(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        if origin.trust == .trusted { return true }
        switch capability {
        case .openLink(let url):
            // Web and mail addresses only: not a local file, an app's own scheme or a network share.
            return linkSchemes.contains(url.scheme?.lowercased() ?? "")
        case .webView(let url):
            // Inline html (nil) is allowed; its base is asked about on its own.
            guard let url else { return true }
            return webViewSchemes.contains(url.scheme?.lowercased() ?? "")
        case .webViewBaseURL(let base):
            // A remote document's own origin, so its relative resources resolve; not another site,
            // whose cookies and storage the html would get, and no local file.
            guard case .remote(let document) = origin.source else { return false }
            return haveSameOrigin(base, document)
        case .webViewUserScripts, .webViewPersistentData:
            // No scripts of its own in its pages, and none of the app's own cookies and storage.
            return false
        case .readLocalFile(let path), .webViewScriptFile(let path):
            // The app's own resources only: not the user's files, a device, or a network share.
            return isInAppResources(path)
        case .windowTitle, .presentModal:
            // Neither the window's title nor a sheet, cover or popover over it: content that is not
            // the app's own could pass itself off as the app.
            return false
        case .load(let source):
            // A local file outside the app's resources (the user's files, a device, a network
            // share) is not loaded; the app's resources and remote addresses are.
            if case .file = source { return false }
            return true
        case .menuCommands, .action:
            return true
        }
    }
}

/// What a WebView loads, by the trust policy: an address it may not show is replaced by a short
/// "Blocked" page, and a base address its inline html may not run under by about:blank. Both are
/// logged. `allows` answers for the WebView's element.
enum WebViewTrust {
    static let blankBase = URL(string: "about:blank")!

    /// Whether the WebView may show `url`.
    @MainActor
    static func showsAddress(_ url: URL, allows: (ActionUICapability) -> Bool, logger: any ActionUILogger) -> Bool {
        guard allows(.webView(url)) else {
            logger.log("WebView not showing \(url.absoluteString): the trust policy refuses it", .warning)
            return false
        }
        return true
    }

    /// Whether a WebView with `count` user scripts runs them: when it has none, or when the policy
    /// allows it (asked as the WebView is made; a refusal is logged).
    @MainActor
    static func runsUserScripts(count: Int, allows: (ActionUICapability) -> Bool, logger: any ActionUILogger) -> Bool {
        guard count > 0 else { return true }
        guard allows(.webViewUserScripts) else {
            logger.log("WebView not running its \(count) user script(s): the trust policy refuses them", .warning)
            return false
        }
        return true
    }

    /// Whether a WebView keeps the app's persistent data store, else a private store of its own.
    @MainActor
    static func keepsPersistentData(allows: (ActionUICapability) -> Bool) -> Bool {
        allows(.webViewPersistentData)
    }

    /// The base address for the WebView's inline html: `base` when the policy allows it, else
    /// about:blank.
    @MainActor
    static func base(_ base: URL?, allows: (ActionUICapability) -> Bool, logger: any ActionUILogger) -> URL {
        guard let base, base != blankBase else { return blankBase }
        guard allows(.webViewBaseURL(base)) else {
            logger.log("WebView html not given the base \(base.absoluteString): the trust policy refuses it", .warning)
            return blankBase
        }
        return base
    }

    /// What a less-trusted WebView does with a navigation its page starts.
    enum Navigation: Equatable {
        /// Load it in the WebView.
        case load
        /// Hand it to the system (another app), as WebKit does with an address it cannot load.
        case open
        /// Neither (logged).
        case refuse
    }

    /// The schemes a page uses inside itself, which stay in the WebView.
    static let pageSchemes: Set<String> = ["about", "data", "blob"]

    /// What a less-trusted WebView does with a navigation to `url` (`isMainFrame`: the page itself,
    /// not a frame in it): a web address loads when the policy shows it (a frame's always does, as
    /// part of the page); the page's own schemes load, and a local file when the policy shows it;
    /// any other address is opened by the system only when the policy allows a link to it (mailto,
    /// by default), else refused.
    @MainActor
    static func navigation(_ url: URL, isMainFrame: Bool, allows: (ActionUICapability) -> Bool,
                           logger: any ActionUILogger) -> Navigation {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            if !isMainFrame || allows(.webView(url)) { return .load }
        } else if pageSchemes.contains(scheme) {
            return .load
        } else if scheme == "file", allows(.webView(url)) {
            // A local file the host's policy lets this WebView show (loaded with loadFileURL).
            return .load
        } else if isMainFrame, allows(.openLink(url)) {
            // The page itself only: a frame (which a page can add without end) opens no other app.
            return .open
        }
        logger.log("WebView not going to \(url.absoluteString): the trust policy refuses it", .warning)
        return .refuse
    }

    /// The page shown in place of an address the policy refuses.
    static func blockedPage(_ url: URL) -> String {
        let text = url.absoluteString.replacing("&", with: "&amp;").replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;").replacing("\"", with: "&quot;")
        return "<!DOCTYPE html><meta charset=\"utf-8\"><p style=\"font-family: sans-serif\">Blocked: \(text)</p>"
    }
}

@MainActor
enum ActionUIDocumentLoader {

    /// Where a LoadableView's text points.
    enum Source: Equatable {
        case remote(URL)
        case file(URL)
    }

    /// The source a LoadableView's text names, or the message to show when it names none:
    ///  - "http://" or "https://" (any case): a remote URL;
    ///  - "file://" (any case): that file URL, which must have a path;
    ///  - a text with "/": a file path;
    ///  - anything else: a resource bundled with the program, by name with its extension, else with
    ///    ".json", else ".plist" (".json" when the name ends in ".plist"). `bundleURL(name, extension)`
    ///    finds a bundled resource.
    static func source(
        for value: String,
        bundleURL: (String, String) -> URL?,
        logger: any ActionUILogger
    ) -> Result<Source, SourceError> {
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            guard let url = URL(string: value) else {
                logger.log("Invalid URL: \(value)", .warning)
                return .failure(SourceError(message: "Invalid URL: \(value)"))
            }
            logger.log("Interpreting value as remote URL: \(value)", .debug)
            return .success(.remote(url))
        }
        if value.lowercased().hasPrefix("file://") {
            guard let url = URL(string: value), !url.path.isEmpty else {
                logger.log("Invalid file URL: \(value)", .warning)
                return .failure(SourceError(message: "Invalid file URL: \(value)"))
            }
            logger.log("Interpreting value as file URL: \(value)", .debug)
            return .success(.file(url))
        }
        if value.contains("/") {
            logger.log("Interpreting value as filePath: \(value)", .debug)
            return .success(.file(URL(fileURLWithPath: value)))
        }
        let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
#if canImport(FoundationEssentials)
        let resourceName = ext.isEmpty ? value : value.replacing(".\(ext)", with: "")
#else
        // Foundation's replace, as before: `replacing` matches by Character and misses ".json"
        // next to a prepended, spacing or joining mark ("a\u{600}.json", "a.json\u{93E}.json").
        let resourceName = ext.isEmpty ? value : value.replacingOccurrences(of: ".\(ext)", with: "")
#endif
        let bundleExt = ext.isEmpty ? "json" : ext
        guard let url = bundleURL(resourceName, bundleExt) ??
                        bundleURL(resourceName, bundleExt == "json" ? "plist" : "json") else {
            logger.log("Bundle resource '\(value)' not found with .json or .plist", .warning)
            return .failure(SourceError(message: "Bundle resource '\(value)' not found"))
        }
        logger.log("Interpreting value as bundle name: \(value)", .debug)
        return .success(.file(url))
    }

    /// Why a LoadableView's text names no source, as the text to show in its place.
    struct SourceError: Error, Equatable {
        let message: String
    }

    /// The contents of the local file at `url`, which must be a regular file once symbolic links
    /// are followed. A document names the path, so it could name a device such as /dev/zero or a
    /// named pipe, and reading one would never end (or never begin) on the main thread.
    /// A file larger than `maximumFileSize` is refused before it is read: larger ActionUI JSON is
    /// refused when it loads anyway (WindowModel.maximumJSONSize), so reading more only costs memory.
    nonisolated static func readRegularFile(_ url: URL) throws -> Data {
        // Not regularFilePath: a missing file keeps the system's own "no such file" error here.
        let path = url.resolvingSymlinksInPath().path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw NotARegularFile(path: url.path) }
        // An Int on Apple (bridged), a UInt in FoundationEssentials, possibly a UInt64 in swift-corelibs.
        let size = (attributes[.size] as? Int) ?? (attributes[.size] as? UInt).map { Int(clamping: $0) }
            ?? (attributes[.size] as? UInt64).map { Int(clamping: $0) }
        if let size, size > maximumFileSize {
            throw ActionUIError("\(url.lastPathComponent) is larger than \(maximumFileSize / (1024 * 1024)) MB")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// The largest file readRegularFile reads (ActionUIConfiguration.limits.maximumJSONSize).
    nonisolated static var maximumFileSize: Int { ActionUIConfiguration.current.limits.maximumJSONSize }

    /// The path of `url` with symbolic links followed, when it names a regular file; nil for a
    /// folder, a device, a pipe, a socket or nothing. For readers that open the file themselves,
    /// such as an image decoder given a path a document named.
    nonisolated static func regularFilePath(_ url: URL) -> String? {
        let path = url.resolvingSymlinksInPath().path
        guard let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType,
              type == .typeRegular else { return nil }
        return path
    }

    /// A path that names something other than a regular file: a folder, a device, a pipe or a socket.
    struct NotARegularFile: Error, CustomStringConvertible {
        let path: String
        var description: String { "\(path) is not a regular file" }
    }

    /// How deep LoadableViews may nest: one whose LoadableViews around it already number this many
    /// is refused (ActionUIConfiguration.limits.maximumNestingDepth).
    nonisolated static var maxNestingDepth: Int { ActionUIConfiguration.current.limits.maximumNestingDepth }

    /// The text a LoadableView's source is known by when the nesting rule compares sources: a remote
    /// URL as written, a file with symbolic links resolved and the path standardized.
    nonisolated static func nestingKey(for source: Source) -> String {
        switch source {
        case .remote(let url): return url.absoluteString
        case .file(let url): return url.resolvingSymlinksInPath().standardizedFileURL.absoluteString
        }
    }

    /// Why the source known as `key` (`nestingKey`) must not load inside LoadableViews showing
    /// `enclosing` (the outermost first), or nil when it may. A document that loads itself, directly
    /// or through others, would load without end; file sources load while the view is built.
    /// Siblings showing the same source are not in `enclosing`, so they stay allowed.
    nonisolated static func nestingRefusal(_ key: String, inside enclosing: [String]) -> String? {
        if enclosing.contains(key) { return "it includes itself" }
        if enclosing.count >= maxNestingDepth { return "LoadableViews are nested more than \(maxNestingDepth) deep" }
        return nil
    }

    /// Where content loaded from `source` came from and how far it is trusted, inside content of
    /// origin `parent` (nil: the host's), into the LoadableView `parentID` (nil: as a window's root).
    /// Remote ActionUI JSON is less trusted unless it came from one of `trustedOrigins` (https
    /// only); a file is trusted only inside one of `resourceFolders` (symbolic links followed); then
    /// the lower of that and the parent's trust, so a bundled file or a trusted server that remote
    /// content names stays less trusted.
    nonisolated static func origin(
        for source: Source,
        inside parent: JSONContentOrigin?,
        parentID: Int?,
        resourceFolders: [String],
        trustedOrigins: [URL] = []
    ) -> JSONContentOrigin {
        let kind: JSONContentOrigin.Source
        let own: JSONContentOrigin.Trust
        switch source {
        case .remote(let url):
            kind = .remote(url)
            own = ActionUIConfiguration.isTrustedOrigin(url, among: trustedOrigins) ? .trusted : .lessTrusted
        case .file(let url):
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            if resourceFolders.contains(where: { ActionUIResourceFolder.isFile(url, inside: $0) }) {
                kind = .resource(path)
                own = .trusted
            } else {
                kind = .file(path)
                own = .lessTrusted
            }
        }
        return JSONContentOrigin(source: kind, trust: min(own, parent?.trust ?? .trusted), parentID: parentID)
    }

    /// Why the LoadableView `parentID` of the window may not load `source`, or nil when it may: the
    /// trust policy is asked (ActionUICapability.load) with the origin of the content the LoadableView
    /// is in, about the source as its content would be classified (a resource, a file elsewhere, a
    /// remote address). Asked before anything is read.
    /// `around`: the origin of the content the LoadableView is in, when the renderer knows it from the
    /// view model it draws the LoadableView with (a template row's, by its container); nil: looked up
    /// by `parentID`.
    static func loadRefusal(_ source: Source, windowUUID: String, parentID: Int, around: JSONContentOrigin? = nil,
                            logger: any ActionUILogger) -> String? {
        let kind = origin(for: source, inside: nil, parentID: nil, resourceFolders: ActionUIRendererHooks.resourceFolders(),
                          trustedOrigins: ActionUIConfiguration.current.trust.trustedOrigins).source
        let allowed = around.map { ActionUIModel.shared.trustPolicy.allows(.load(kind), for: $0) }
            ?? ActionUIModel.shared.allows(.load(kind), windowUUID: windowUUID, viewID: parentID)
        guard !allowed else { return nil }
        logger.log("LoadableView \(parentID): not loading \(nestingKey(for: source)): the trust policy refuses it", .warning)
        return "the trust policy refuses it"
    }

    /// "plist" for a file or URL whose name ends in ".plist" (any case), else "json".
    static func format(of url: URL) -> String {
        url.pathExtension.lowercased() == "plist" ? "plist" : "json"
    }

    /// Loads `data`, read from `source` (nil: data the host passed in itself), as the window's
    /// content (`isContentView`) or as the sub-view of the LoadableView `parentID`, and returns its
    /// root element. Each element it loads is given the content's origin (see `origin(for:)`).
    static func load(
        data: Data,
        format: String,
        windowUUID: String,
        isContentView: Bool,
        parentID: Int,
        source: Source?,
        around: JSONContentOrigin? = nil
    ) throws -> ActionUIElement {
        let origin = source.map { resolvedOrigin(for: $0, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID, around: around) }
        if isContentView {
            return try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID, origin: origin)
        }
        return try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID, parentID: parentID, origin: origin)
    }

    /// The origin of content loaded from `source` into the window: as a root (`isContentView`), or
    /// into its LoadableView `parentID`. Classified (origin(for:)), then the host's trust policy
    /// has the last word.
    /// `around`: the origin of the content the LoadableView is in, when the renderer knows it (see
    /// loadRefusal); nil: looked up by `parentID`. The policy gets no parent only for a window's
    /// root: a LoadableView whose surroundings cannot be told gets `unknownSurroundings`, less
    /// trusted, so a policy that trusts "no parent and my file", as a window's root, cannot be made
    /// to trust that file inside content it does not know.
    static func resolvedOrigin(for source: Source, windowUUID: String, isContentView: Bool, parentID: Int,
                               around: JSONContentOrigin? = nil) -> JSONContentOrigin {
        // A sub-view's parent is the LoadableView, an element of the content around it.
        let parent: JSONContentOrigin?
        if isContentView {
            parent = nil
        } else if let around {
            parent = around
        } else if let parentModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] {
            parent = parentModel.origin ?? .host
        } else {
            // Id 0 is the host's own loader. Any other LoadableView with no view model (one in a
            // template row the renderer did not describe, a blueprint the window has no model for)
            // has no known trust: less trusted, so a miss cannot make remote content's choice of
            // file read as the host's.
            parent = parentID == 0 ? .host : unknownSurroundings
        }
        let classified = Self.origin(for: source, inside: parent, parentID: isContentView ? nil : parentID,
                                     resourceFolders: ActionUIRendererHooks.resourceFolders(),
                                     trustedOrigins: ActionUIConfiguration.current.trust.trustedOrigins)
        let trust = ActionUIModel.shared.trustPolicy.trust(for: classified.source, inside: parent, byDefault: classified.trust)
        return trust == classified.trust ? classified : JSONContentOrigin(source: classified.source, trust: trust, parentID: classified.parentID)
    }

    /// The parent the trust policy gets for a LoadableView whose surroundings cannot be told: less
    /// trusted, never nil, which means a window's root.
    static let unknownSurroundings = JSONContentOrigin(source: .host, trust: .lessTrusted, parentID: nil)

    /// For a LoadableView drawn with `model`: the origin of the content it is in when it is in a
    /// template row (its row's container's; less trusted when that cannot be told), else nil (the
    /// LoadableView's own view model, by its id, tells it).
    static func templateSurroundings(windowUUID: String, model: ViewModel) -> JSONContentOrigin? {
        guard let container = model.templateContext?.parentID else { return nil }
        return ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: container) ?? unknownSurroundings
    }

    /// Why a LoadableView drawn with `model` in a template row must not load, or nil when it may: its
    /// id is another element's in the window, and its content would load into that element's place
    /// (the window keeps a LoadableView's content by its id).
    static func templateIDRefusal(windowUUID: String, viewID: Int, model: ViewModel, logger: any ActionUILogger) -> String? {
        guard model.templateContext != nil,
              let registered = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[viewID],
              registered !== model else { return nil }
        logger.log("LoadableView \(viewID) in a template row: not loading: id \(viewID) is another element's in the window", .warning)
        return "id \(viewID) is another element's in the window"
    }

    /// Fetches `url` with `fetch`, then loads it as `load` does, with the format of the URL. `fetch`
    /// gives the data and the address it finally came from, after redirects, which decides its
    /// origin: a trusted server that redirects elsewhere does not make the other server's JSON trusted.
    static func loadRemote(
        url: URL,
        windowUUID: String,
        isContentView: Bool,
        parentID: Int,
        around: JSONContentOrigin? = nil,
        logger: any ActionUILogger,
        fetch: (URL) async throws -> (data: Data, finalURL: URL)
    ) async throws -> ActionUIElement {
        let (data, finalURL) = try await fetch(url)
        let format = format(of: url)
        logger.log("Determined format '\(format)' for remote URL \(url)", .debug)
        if finalURL != url {
            logger.log("Remote URL \(url) was redirected to \(finalURL)", .debug)
            // The LoadableView asked the trust policy about `url`; the content came from finalURL.
            if !isContentView, let refusal = loadRefusal(.remote(finalURL), windowUUID: windowUUID, parentID: parentID, around: around, logger: logger) {
                throw ActionUIError("Could not load \(url.absoluteString): it was redirected to \(finalURL.absoluteString), and \(refusal)")
            }
        }
        let element = try load(data: data, format: format, windowUUID: windowUUID, isContentView: isContentView,
                               parentID: parentID, source: .remote(finalURL), around: around)
        logger.log("Successfully loaded \(format) for LoadableView from remote \(url)", .debug)
        return element
    }

    /// Fires a LoadableView's viewDidLoadActionID once per source: again only when the LoadableView
    /// `parentID` of the window loads a different source. Kept outside the view models, whose
    /// observed states would render the view again.
    @MainActor
    final class ViewDidLoad {
        private var loadedSources: [String: String] = [:]

        /// Fires `actionID` (viewID `parentID`, viewPartID 0) unless there is none, the window has no
        /// such element, or this source was the last one fired for it.
        func fire(source: String, windowUUID: String, parentID: Int, actionID: String?) {
            guard let actionID else { return }
            guard ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] != nil else { return }

            let key = "\(windowUUID)_\(parentID)"
            guard loadedSources[key] != source else { return }
            loadedSources[key] = source
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: parentID, viewPartID: 0)
        }
    }
}

#if !canImport(FoundationEssentials)
/// On Apple, the message a LoadableView shows for a path that is not a regular file, through
/// localizedDescription. LocalizedError is Foundation's, which Core imports only on Apple. Next to
/// the type, as ActionUIError's conformance is: a conformance is found only by a cast at run time,
/// and the linker may drop a file that holds nothing else a host refers to.
extension ActionUIDocumentLoader.NotARegularFile: LocalizedError {
    var errorDescription: String? { description }
}
#endif
