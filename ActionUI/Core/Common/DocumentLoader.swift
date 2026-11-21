// Core/Common/DocumentLoader.swift
/*
 Loading a description into a window, without the views: where a LoadableView's text points (a
 remote URL, a file, a bundled resource), the format of a file or URL, loading the data as the
 window's content or as a sub-view of a LoadableView, and firing a LoadableView's viewDidLoadActionID
 once per source. Where loaded content came from and how far it is trusted (DocumentOrigin): the
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
public final class DocumentOrigin: Sendable, Equatable, CustomStringConvertible {
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
    public static let host = DocumentOrigin(source: .host, trust: .trusted, parentID: nil)

    public static func == (lhs: DocumentOrigin, rhs: DocumentOrigin) -> Bool {
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

/// At most `loads` LoadableView loads per window in any `seconds` (ActionUIModel.loadBudget).
public struct ActionUILoadBudget: Sendable, Equatable {
    public var loads: Int
    public var seconds: Double

    public init(loads: Int, seconds: Double) {
        self.loads = loads
        self.seconds = seconds
    }
}

/// Something a part of a window's content may do, which the trust policy is asked about
/// (ActionUIModel.allows). The renderers ask before each.
public enum ActionUICapability: Sendable, Equatable {
    /// A LoadableView loading this source (the load budget and size caps apply whatever the answer).
    case load(DocumentOrigin.Source)
    /// Opening an address: a Link, or openURL.
    case openLink(URL)
    /// A WebView showing this address; nil for inline html.
    case webView(URL?)
    /// The base address a WebView's inline html runs under (its origin, for cookies and storage).
    case webViewBaseURL(URL)
    /// A WebView user script read from this file.
    case webViewScriptFile(String)
    /// An Image, Canvas image, VideoPlayer or AsyncImage reading this local file.
    case readLocalFile(String)
    /// Setting the window's title (navigationTitle on a window root, a WindowGroup title).
    case windowTitle
    /// Presenting a sheet, full-screen cover, popover, alert or confirmation dialog.
    case presentModal
    /// Adding menu commands (CommandMenu, CommandGroup).
    case menuCommands
    /// Firing this action.
    case action(String)
}

/// The host's say over how far content is trusted and what it may do,
/// set on ActionUIModel.shared.trustPolicy before loading. One object serves every window; a host
/// that wants rules per window switches on the origin's parentID or keeps its own map.
public protocol ActionUITrustPolicy: Sendable {
    /// The trust of content loaded from `source` inside content of origin `parent` (nil for a
    /// window's root, or for a LoadableView whose own trust is unknown), given what ActionUI
    /// decides `byDefault`. The default implementation keeps that.
    @MainActor func trust(for source: DocumentOrigin.Source, inside parent: DocumentOrigin?,
                          byDefault: DocumentOrigin.Trust) -> DocumentOrigin.Trust
    /// Whether content of `origin` may do `capability`. The default implementation is
    /// DefaultTrustPolicy's.
    @MainActor func allows(_ capability: ActionUICapability, for origin: DocumentOrigin) -> Bool
}

extension ActionUITrustPolicy {
    @MainActor public func trust(for source: DocumentOrigin.Source, inside parent: DocumentOrigin?,
                                 byDefault: DocumentOrigin.Trust) -> DocumentOrigin.Trust {
        byDefault
    }

    @MainActor public func allows(_ capability: ActionUICapability, for origin: DocumentOrigin) -> Bool {
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
    /// WebView (webViewSchemes), and give its inline html a base address only of its own document's
    /// origin, and for now do anything else (each further refusal comes with the renderer change
    /// that enforces it).
    public static func allowsByDefault(_ capability: ActionUICapability, for origin: DocumentOrigin) -> Bool {
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
        case .load, .webViewScriptFile, .readLocalFile, .windowTitle, .presentModal, .menuCommands, .action:
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
    /// A file larger than `maximumFileSize` is refused before it is read: a document is refused at
    /// 16 MB when it loads anyway (WindowModel.maximumDocumentSize), so reading more only costs memory.
    nonisolated static func readRegularFile(_ url: URL) throws -> Data {
        // Not regularFilePath: a missing file keeps the system's own "no such file" error here.
        let path = url.resolvingSymlinksInPath().path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw NotARegularFile(path: url.path) }
        // An Int on Apple (bridged), possibly a UInt64 in swift-corelibs.
        let size = (attributes[.size] as? Int) ?? (attributes[.size] as? UInt64).map { Int(clamping: $0) }
        if let size, size > maximumFileSize {
            throw ActionUIError("\(url.lastPathComponent) is larger than \(maximumFileSize / (1024 * 1024)) MB")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// The largest file readRegularFile reads (the document cap, 16 MB).
    nonisolated static let maximumFileSize = 16 * 1024 * 1024

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
    /// is refused.
    nonisolated static var maxNestingDepth: Int { 16 }

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
    /// A remote document is less trusted; a file is trusted only inside one of `resourceFolders`
    /// (symbolic links followed); then the lower of that and the parent's trust, so a bundled file
    /// that remote content names stays less trusted.
    nonisolated static func origin(
        for source: Source,
        inside parent: DocumentOrigin?,
        parentID: Int?,
        resourceFolders: [String]
    ) -> DocumentOrigin {
        let kind: DocumentOrigin.Source
        let own: DocumentOrigin.Trust
        switch source {
        case .remote(let url):
            kind = .remote(url)
            own = .lessTrusted
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
        return DocumentOrigin(source: kind, trust: min(own, parent?.trust ?? .trusted), parentID: parentID)
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
        source: Source?
    ) throws -> ActionUIElement {
        let origin = source.map { resolvedOrigin(for: $0, windowUUID: windowUUID, isContentView: isContentView, parentID: parentID) }
        if isContentView {
            return try ActionUIModel.shared.loadDescription(from: data, format: format, windowUUID: windowUUID, origin: origin)
        }
        return try ActionUIModel.shared.loadSubViewDescription(from: data, format: format, windowUUID: windowUUID, parentID: parentID, origin: origin)
    }

    /// The origin of content loaded from `source` into the window: as a root (`isContentView`), or
    /// into its LoadableView `parentID`. Classified (origin(for:)), then the host's trust policy
    /// has the last word.
    static func resolvedOrigin(for source: Source, windowUUID: String, isContentView: Bool, parentID: Int) -> DocumentOrigin {
        // A sub-view's parent is the LoadableView, an element of the content around it.
        let parentModel = isContentView ? nil : ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID]
        // A LoadableView with no view model of its own (one in a template row, a blueprint the
        // window has no model for) has no known trust: less trusted, so a miss cannot make remote
        // content's choice of file read as the host's. Id 0 is the host's own loader.
        let unknownParent = !isContentView && parentID != 0 && parentModel == nil
        let parent: DocumentOrigin? = isContentView || unknownParent ? nil : (parentModel?.origin ?? .host)
        let classified = Self.origin(for: source, inside: parent, parentID: isContentView ? nil : parentID,
                                     resourceFolders: ActionUIRendererHooks.resourceFolders())
        let byDefault: DocumentOrigin.Trust = unknownParent ? .lessTrusted : classified.trust
        let trust = ActionUIModel.shared.trustPolicy.trust(for: classified.source, inside: parent, byDefault: byDefault)
        return trust == classified.trust ? classified : DocumentOrigin(source: classified.source, trust: trust, parentID: classified.parentID)
    }

    /// Fetches `url` with `fetch`, then loads it as `load` does, with the format of the URL.
    static func loadRemote(
        url: URL,
        windowUUID: String,
        isContentView: Bool,
        parentID: Int,
        logger: any ActionUILogger,
        fetch: (URL) async throws -> Data
    ) async throws -> ActionUIElement {
        let data = try await fetch(url)
        let format = format(of: url)
        logger.log("Determined format '\(format)' for remote URL \(url)", .debug)
        let element = try load(data: data, format: format, windowUUID: windowUUID, isContentView: isContentView,
                               parentID: parentID, source: .remote(url))
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
