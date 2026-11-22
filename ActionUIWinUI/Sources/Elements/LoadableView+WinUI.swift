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
 - A file is read only when it is a regular file (ActionUIDocumentLoader.readRegularFile). Less-trusted
   content (ActionUI JSON from a server or from a file outside the app's resources) loads no file on a
   share or a device (\\server\share, \\?\ and the like), never touched.

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
        let source: Result<ActionUIDocumentLoader.Source, ActionUIDocumentLoader.SourceError>
        if isWindowsPath(value) {
            source = .success(.file(URL(fileURLWithPath: value)))
        } else {
            source = ActionUIDocumentLoader.source(for: value, bundleURL: { name, ext in
                let file = "\(name).\(ext)"
                let url = folder?.appendingPathComponent(file) ?? URL(fileURLWithPath: file)
                // Not looked for on a share by less-trusted content: refused below, never touched.
                if !trusted, LinkTrust.isNetworkPath(LinkTrust.filePath(of: url)) {
                    return url
                }
                return ActionUIDocumentLoader.regularFilePath(url) != nil ? url : nil
            }, logger: logger)
        }
        let windowUUID = node.windowModel.windowUUID
        let parentID = node.element.id
        let actionID = Props(node.properties).viewDidLoadActionID
        if case .success(let found) = source {
            // Less-trusted content loads no file on a share or a device: reading it, even testing it
            // (the nesting key follows symbolic links), would reach the server with the user's
            // credentials.
            if case .file(let url) = found, !trusted {
                let path = LinkTrust.filePath(of: url)
                if LinkTrust.isNetworkPath(path) {
                    logger.log("LoadableView: not loading \(path) for element \(node.element.id): less-trusted content reads no network or device path", .warning)
                    state.status = message("Failed to load view: the trust policy refuses \(path)", error: true)
                    return
                }
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
            if !actionUIWinUIFetchURL(url.absoluteString, fetched, context) {
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
    fileprivate static func finished(_ box: FetchBox, data: Data?, failure: String?) {
        guard let node = box.node, let state = box.state, node.isAttached, state.generation == box.generation else { return }
        let logger = ActionUIModel.shared.logger
        let url = box.url
        state.status = nil
        if let data {
            let format = ActionUIDocumentLoader.format(of: url)
            do {
                state.element = try ActionUIDocumentLoader.load(data: data, format: format, windowUUID: node.windowModel.windowUUID,
                                                               isContentView: false, parentID: node.element.id, source: .remote(url))
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

    /// Whether `value` is a Windows path Core would not take for one: with a backslash, or a drive
    /// letter and a colon ("C:\docs\a.json", "C:a.json"). An http or https URL is never one, even
    /// with a backslash in it (in its query), as Core takes it for a remote URL first.
    static func isWindowsPath(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") { return false }
        if value.contains("\\") { return true }
        let characters = Array(value.prefix(2))
        return characters.count == 2 && characters[1] == ":" && characters[0].isASCII && characters[0].isLetter
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
private let fetched: ActionUIWinUIDataCompletion = { context, bytes, length, error in
    guard let context else { return }
    let data = bytes.map { Data(bytes: $0, count: length) }
    let failure = error.map { String(cString: $0) }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let box = Unmanaged<FetchBox>.fromOpaque(pointer).takeRetainedValue()
        LoadableView.finished(box, data: data, failure: failure)
    }
}
