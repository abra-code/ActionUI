// Sources/Elements/LoadableView+WinUI.swift
/*
 LoadableView on WinUI: the description its source names (the runtime value, else url, filePath or
 name, as on Apple), loaded into the window as the LoadableView's sub-view (Core's
 ActionUIDocumentLoader) and shown as its one child, as a one-child ZStack holds it, following the
 Linux renderer (LoadableView+Adwaita.swift):

 - A file loads while the LoadableView updates, as SwiftUI's FileLoadableView loads in its init: a
   path (with "/", or a Windows path with "\" or a drive letter, which Core would take for a name),
   or a file URL. An http or https URL loads without blocking the window (Windows' HTTP client,
   actionUIWinUIFetchURL), a spinning ring showing meanwhile, as SwiftUI's RemoteLoadableView shows a
   ProgressView.
 - viewDidLoadActionID fires once per source, after the sub-view has loaded (Core's ViewDidLoad).
 - What cannot be loaded shows a message in its place, as on Apple: "No valid source provided" for no
   source, the source's error (an invalid URL, a name not found), or "Failed to load view: ..." in
   the theme's critical (error) color for a file or URL that did not load or parse.
 - A new source loads again, replacing the sub-view and its view models (WindowModel drops the old
   ones); the same source is not loaded again.
 - name is a file of that name (with .json, else .plist, when it has no extension) in the folder of
   the file an enclosing LoadableView loaded, else in the current folder (where a Windows host's
   documents are; Windows has no app bundle).
 - A source that a LoadableView around this one already shows, or one nested more than 16 deep, is
   refused with "Failed to load view: ..." by Core's nesting rule, as SwiftUI's LoadableNestingGuard.
 - Downloaded JSON is judged by the address it finally came from, after redirects (a trusted origin of
   the host's configuration is trusted only when the JSON came from it), and the trust policy is asked
   again about that address.
 - A download is read up to the cap on ActionUI JSON (16 MB; refused at once on a longer
   Content-Length) and given up after 120 seconds; redirects are followed only to http and https, never
   from https to http, at most 20, as on Apple and Linux.
 - An address less-trusted content names is fetched with nothing of the user's or the app's (WinHTTP,
   actionUIWinUIFetchURLPrivately): no cookies sent or kept, no Windows sign-in to the server or a proxy
   (which Windows' HTTP client gives an intranet server on its own), no client certificate, no
   credential dialog; a server that asks for a sign-in is a failure. The app's own content keeps
   Windows' HTTP client and its settings.
 - The host's trust policy is asked before anything is read (ActionUICapability.load, for the content
   the LoadableView is in), as on Apple and Linux: a refused source shows "Failed to load view: ...".
 - A file is read only when it is a regular file (ActionUIDocumentLoader.readRegularFile). Less-trusted
   content (ActionUI JSON from a server or from a file outside the app's resources) loads no file on a
   share or a device (\\server\share, \\?\ and the like), decided from the text before anything touches
   the path. A path or a name becomes a file URL without the file system being asked whether it is a
   folder (which URL(fileURLWithPath:) asks, opening the path).

 Not yet: the message in the LoadableView's place takes none of its text appearance (font,
 foregroundStyle); a file it may not read shows the system's error text, not Apple's words for it.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI
import Dispatch

/// The limit on a LoadableView's download: nil, the cap on ActionUI JSON (WindowModel.maximumJSONSize).
/// A test tool lowers it to see a download refused.
@MainActor package enum LoadableFetch {
    package static var maximumBytes: Int64?
    /// The limit on a download's time: nil, 120 seconds. A test tool lowers it to see a download given up.
    package static var timeoutSeconds: Double?
}

/// What a LoadableView shows, kept in its node's state.
@MainActor final class LoadableState {
    let stack: ZStackLayout
    /// The source text last loaded (or tried); a new one loads again.
    var source: String?
    /// The loaded sub-view's root element, shown as the child.
    var element: ActionUIElement?
    /// What shows instead of a sub-view: a ring while a URL loads, or a message.
    var status: WinUIObject?
    /// Counts the loads: a URL that finishes after a newer source was set is dropped.
    var generation = 0
    /// The folder of the file loaded, where a LoadableView inside it finds its `name`.
    var loadedFolder: URL?
    /// The source being shown, as Core's nesting rule knows it.
    var nestingKey: String?

    init(stack: ZStackLayout) {
        self.stack = stack
    }
}

extension LoadableView: ActionUIWinUIRenderer {
    /// viewDidLoadActionID once per source, for every LoadableView on Windows.
    private static let viewDidLoad = ActionUIDocumentLoader.ViewDidLoad()

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let stack = try ZStackLayout()
        node.state = LoadableState(stack: stack)
        return stack.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? LoadableState else { return }
        let value = initialValue(node.model) as? String ?? ""
        if value != state.source {
            state.source = value
            load(value, node, state)
        }
        let children = node.syncChildren(state.element.map { [$0] } ?? [])
        if let status = state.status {
            state.stack.setItems([ZStackLayout.Item(view: status)])
        } else {
            state.stack.setItems(children.compactMap { child in
                guard !child.takesNoPlace, let view = child.outerView else { return nil }
                return ZStackLayout.Item(view: view, expansion: child.expansion, cap: child.caps)
            })
        }
    }

    private static func load(_ value: String, _ node: RenderNode, _ state: LoadableState) {
        let logger = ActionUIModel.shared.logger
        state.generation &+= 1
        state.element = nil
        state.loadedFolder = nil
        state.nestingKey = nil
        state.status = nil
        guard !value.isEmpty else {
            logger.log("No valid source for LoadableView, displaying error text", .warning)
            state.status = message("No valid source provided", error: false)
            return
        }
        let folder = documentFolder(of: node)
        let trusted = LinkTrust.isTrusted(node)
        // Less-trusted content loads no file on a share or a device: opening it, even asking whether
        // it is a folder (as URL(fileURLWithPath:) does), reaches the server with the user's Windows
        // credentials. Decided from the text alone, before anything below can touch the path.
        if !trusted, let path = namedPath(value, folder: folder), LinkTrust.isNetworkPath(path) {
            refuseNetworkPath(path, node, state)
            return
        }
        let source: Result<ActionUIDocumentLoader.Source, ActionUIDocumentLoader.SourceError>
        if isPathText(value) {
            source = .success(.file(LinkTrust.fileURL(path: value)))
        } else {
            source = ActionUIDocumentLoader.source(for: value, bundleURL: { name, ext in
                let file = "\(name).\(ext)"
                let url = folder?.appending(path: file, directoryHint: .notDirectory) ?? LinkTrust.fileURL(path: file)
                return ActionUIDocumentLoader.regularFilePath(url) != nil ? url : nil
            }, logger: logger)
        }
        let windowUUID = node.windowModel.windowUUID
        let parentID = node.element.id
        let actionID = Props(node.properties).viewDidLoadActionID
        if case .success(let found) = source {
            // The same rule for the URL the text became, in case it names a share the text check
            // above did not see; before the trust policy and the nesting key, which follow symbolic links.
            if case .file(let url) = found, !trusted {
                let path = LinkTrust.filePath(of: url)
                if LinkTrust.isNetworkPath(path) {
                    refuseNetworkPath(path, node, state)
                    return
                }
            }
            // The trust policy may refuse the source (ActionUICapability.load), before anything is read,
            // as on Apple and Linux; after the share check, since classifying a file resolves its path.
            if let refusal = ActionUIDocumentLoader.loadRefusal(found, windowUUID: windowUUID, parentID: parentID, logger: logger) {
                state.status = message("Failed to load view: \(refusal)", error: true)
                return
            }
            let key = ActionUIDocumentLoader.nestingKey(for: found)
            if let refusal = ActionUIDocumentLoader.nestingRefusal(key, inside: enclosingNestingKeys(of: node)) {
                logger.log("LoadableView: not loading \(key): \(refusal)", .error)
                state.status = message("Failed to load view: \(refusal)", error: true)
                return
            }
            state.nestingKey = key
        }
        switch source {
        case .failure(let error):
            state.status = message(error.message, error: false)
        case .success(.file(let url)):
            let format = ActionUIDocumentLoader.format(of: url)
            do {
                let data = try readFile(url)
                state.element = try ActionUIDocumentLoader.load(data: data, format: format, windowUUID: windowUUID,
                                                               isContentView: false, parentID: parentID, source: .file(url))
                state.loadedFolder = url.deletingLastPathComponent()
                logger.log("Successfully loaded \(format) for LoadableView from \(url.absoluteString)", .debug)
                // After this sync, as SwiftUI fires it after the body that loaded.
                let fired = url.absoluteString
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        viewDidLoad.fire(source: fired, windowUUID: windowUUID, parentID: parentID, actionID: actionID)
                    }
                }
            } catch {
                logger.log("Failed to load description for LoadableView from \(url.absoluteString): \(error)", .error)
                state.status = message("Failed to load view: \(failureText(error))", error: true)
            }
        case .success(.remote(let url)):
            state.status = WinUIObject(adopting: actionUIWinUIProgressCreate(ActionUIWinUIProgressRing))
            let box = FetchBox(node: node, state: state, generation: state.generation, url: url, actionID: actionID)
            let context = Unmanaged.passRetained(box).toOpaque()
            // Read up to the cap on ActionUI JSON and given up after 120 seconds, as on Apple and Linux.
            let limit = LoadableFetch.maximumBytes ?? Int64(WindowModel.maximumJSONSize)
            let seconds = LoadableFetch.timeoutSeconds ?? 120
            // Less-trusted content's address is fetched with nothing of the user's or the app's (no
            // cookies, no Windows sign-in, no credential dialog), as Apple's private session does; the
            // app's own content keeps Windows' HTTP client.
            let started = trusted ? actionUIWinUIFetchURL(url.absoluteString, limit, seconds, fetched, context)
                                  : actionUIWinUIFetchURLPrivately(url.absoluteString, limit, seconds, fetched, context)
            if !started {
                // Never called back: the box is let go here.
                Unmanaged<FetchBox>.fromOpaque(context).release()
                let why = WinUIError.last("fetching \(url.absoluteString)")
                logger.log("LoadableView: \(why)", .error)
                state.status = message("Failed to load view: \(why)", error: true)
            }
        }
    }

    /// A remote description arrived (`data`), or did not (`failure`): loaded into the window when it is
    /// still this LoadableView's current load.
    fileprivate static func finished(_ box: FetchBox, data: Data?, finalURL finalText: String?, failure: String?) {
        guard let node = box.node, let state = box.state, node.isAttached, state.generation == box.generation else { return }
        let logger = ActionUIModel.shared.logger
        let url = box.url
        state.status = nil
        if let data {
            let format = ActionUIDocumentLoader.format(of: url)
            do {
                // The content is judged by the address it finally came from (a trusted server's redirect
                // to another server gives less-trusted content), as on Apple and Linux; one Foundation
                // cannot read is refused rather than taken for the address asked for.
                let finalURL: URL
                if let finalText {
                    // Nor one with a backslash or a user name, where Windows' and Foundation's readings of
                    // the host could differ ("https://a.example\@b.example/" is b.example to Foundation):
                    // the address judged must be the one the bytes came from.
                    guard let read = URL(string: finalText), !finalText.contains("\\"), read.user == nil else {
                        throw ActionUIError("it was redirected to an address that cannot be read")
                    }
                    finalURL = read
                } else {
                    finalURL = url
                }
                if finalURL != url {
                    logger.log("Remote URL \(url) was redirected to \(finalURL)", .debug)
                    // The trust policy was asked about `url`; the content came from finalURL.
                    if let refusal = ActionUIDocumentLoader.loadRefusal(.remote(finalURL), windowUUID: node.windowModel.windowUUID,
                                                                        parentID: node.element.id, logger: logger) {
                        throw ActionUIError("it was redirected to \(finalURL.absoluteString), and \(refusal)")
                    }
                }
                state.element = try ActionUIDocumentLoader.load(data: data, format: format, windowUUID: node.windowModel.windowUUID,
                                                               isContentView: false, parentID: node.element.id, source: .remote(finalURL))
                logger.log("Successfully loaded \(format) for LoadableView from remote \(url)", .debug)
                viewDidLoad.fire(source: url.absoluteString, windowUUID: node.windowModel.windowUUID, parentID: node.element.id,
                                 actionID: box.actionID)
            } catch {
                logger.log("Failed to load remote description for LoadableView from \(url.absoluteString): \(error)", .error)
                state.status = message("Failed to load view: \(failureText(error))", error: true)
            }
        } else {
            let why = failure ?? "the request failed"
            logger.log("Failed to load remote description for LoadableView from \(url.absoluteString): \(why)", .error)
            state.status = message("Failed to load view: \(why)", error: true)
        }
        SyncScheduler.shared.markDirty(node)
    }

    /// A file's contents; a missing one fails with Apple's words for it.
    private static func readFile(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadFailure(text: "The file \"\(url.lastPathComponent)\" couldn't be opened because there is no such file.")
        }
        return try ActionUIDocumentLoader.readRegularFile(url)
    }

    /// Why a load failed, in the words Apple's localizedDescription uses for the common cases.
    static func failureText(_ error: any Error) -> String {
        if let failure = error as? LoadFailure {
            return failure.text
        }
        // A description that does not parse: JSONParser's error for JSON text, a decoder's for the rest.
        if error is JSONParseError || error is DecodingError {
            return "The data couldn't be read because it isn't in the correct format."
        }
        return "\(error)"
    }

    /// Whether `value` is a path, which the renderer turns into a file URL itself, without asking the
    /// file system anything (Core's would ask whether it is a folder): with a slash or a backslash,
    /// or a drive letter and a colon ("C:\docs\a.json", "C:a.json", "docs/a.json"). An http, https or
    /// file URL is never one, even with a backslash in it (in its query), as Core reads those first.
    static func isPathText(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") || lowercased.hasPrefix("file://") {
            return false
        }
        if value.contains("\\") || value.contains("/") { return true }
        let characters = Array(value.prefix(2))
        return characters.count == 2 && characters[1] == ":" && characters[0].isASCII && characters[0].isLetter
    }

    /// The local path `value` names, from its text alone (nothing here touches the file system), or nil
    /// for an http or https address or a file URL that does not parse: a path as written; a file URL's
    /// path, a share for one with a host ("file://server/share/a.json"); a name, in `folder` (the
    /// folder of the file an enclosing LoadableView loaded), else in the current folder.
    static func namedPath(_ value: String, folder: URL?) -> String? {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") { return nil }
        if lowercased.hasPrefix("file://") {
            return URL(string: value).map { LinkTrust.filePath(of: $0) }
        }
        if isPathText(value) { return value }
        let base = folder.map { LinkTrust.filePath(of: $0) } ?? FileManager.default.currentDirectoryPath
        return base.hasSuffix("\\") || base.hasSuffix("/") ? base + value : base + "\\" + value
    }

    /// Shows and logs the refusal of a file on a share or a device for less-trusted content.
    private static func refuseNetworkPath(_ path: String, _ node: RenderNode, _ state: LoadableState) {
        ActionUIModel.shared.logger.log("LoadableView: not loading \(path) for element \(node.element.id): less-trusted content reads no network or device path", .warning)
        state.status = message("Failed to load view: the trust policy refuses \(path)", error: true)
    }

    /// A message in the LoadableView's place, wrapped; in the critical color for a load that failed, as
    /// SwiftUI shows it in red.
    private static func message(_ text: String, error: Bool) -> WinUIObject? {
        guard let label = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            ActionUIModel.shared.logger.log("LoadableView: \(WinUIError.last("making a message"))", .error)
            return nil
        }
        if !actionUIWinUITextBlockSetText(label.pointer, text) || !actionUIWinUITextBlockSetWraps(label.pointer, true) {
            ActionUIModel.shared.logger.log("LoadableView: \(WinUIError.last("showing a message"))", .error)
        }
        if error {
            Paint.apply(.theme("SystemFillColorCriticalBrush"), ActionUIWinUIBrushForeground, to: label, what: "a LoadableView's error")
        }
        return label
    }

    /// The folder of the file the nearest enclosing LoadableView loaded; nil: the current folder.
    private static func documentFolder(of node: RenderNode) -> URL? {
        var ancestor = node.parent
        while let current = ancestor {
            if let state = current.state as? LoadableState {
                return state.loadedFolder
            }
            ancestor = current.parent
        }
        return nil
    }

    /// The sources the LoadableViews around `node` show, the outermost first: only those whose loaded
    /// sub-view (their child node) holds `node`.
    private static func enclosingNestingKeys(of node: RenderNode) -> [String] {
        var keys: [String] = []
        var inner = node
        while let current = inner.parent {
            if current.orderedChildren.contains(where: { $0 === inner }), let state = current.state as? LoadableState,
               let key = state.nestingKey {
                keys.append(key)
            }
            inner = current
        }
        return keys.reversed()
    }
}

/// A load's failure with the text to show.
private struct LoadFailure: Error {
    let text: String
}

/// A remote load under way, held by the shim until its completion.
@MainActor private final class FetchBox {
    weak var node: RenderNode?
    weak var state: LoadableState?
    let generation: Int
    let url: URL
    let actionID: String?

    init(node: RenderNode, state: LoadableState, generation: Int, url: URL, actionID: String?) {
        self.node = node
        self.state = state
        self.generation = generation
        self.url = url
        self.actionID = actionID
    }
}

// The bytes cross the main actor's closure as a Data (a pointer is not Sendable).
private let fetched: ActionUIWinUIDataCompletion = { context, bytes, length, finalURL, error in
    guard let context else { return }
    let data = bytes.map { Data(bytes: $0, count: length) }
    let finalText = finalURL.map { String(cString: $0) }
    let failure = error.map { String(cString: $0) }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let box = Unmanaged<FetchBox>.fromOpaque(pointer).takeRetainedValue()
        LoadableView.finished(box, data: data, finalURL: finalText, failure: failure)
    }
}
