// Sources/Elements/LoadableView+Adwaita.swift
/*
 LoadableView on GTK: the description its source names (the runtime value, else url, filePath or
 name, as on Apple), loaded into the window as the LoadableView's sub-view (Core's
 ActionUIDocumentLoader) and shown as its one child, as a one-child ZStack holds it (SwiftUI shows
 the loaded view in its place, which a one-child ZStack lays out the same).

 - A file (a path, or a file URL) loads while the LoadableView updates, as SwiftUI's
   FileLoadableView loads in its init; an http or https URL loads without blocking the window
   (URLLoader), a spinner showing meanwhile, as SwiftUI's RemoteLoadableView shows a ProgressView.
 - viewDidLoadActionID fires once per source, after the sub-view has loaded (Core's ViewDidLoad).
 - What cannot be loaded shows a message in its place, as on Apple: "No valid source provided"
   for no source, the source's error (an invalid URL), or "Failed to load view: ..." in the error
   color for a file or URL that did not load or parse.
 - A new source loads again, replacing the sub-view and its view models (WindowModel drops the old
   ones); the same source is not loaded again.
 - name is a file of that name in the folder of the document holding the LoadableView (the file an
   enclosing LoadableView loaded, else the window's document), then in the app's bundle (AppBundle);
   found nowhere, it shows Core's "not found" message.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

private let loadableStateKey = AttachKey<LoadableState>("actionui-loadable-state")

/// What a LoadableView shows, kept on its widget.
@MainActor private final class LoadableState {
    /// The source text last loaded (or tried); a new one loads again.
    var source: String?
    /// The loaded sub-view's root element, shown as the child.
    var element: ActionUIElement?
    /// What shows instead of a sub-view: a spinner while a URL loads, or a message.
    var status: WidgetPointer?
    /// Counts the loads: a URL that finishes after a newer source was set is dropped.
    var generation = 0
    /// The folder of the file loaded, where a LoadableView inside it finds its `name`.
    var loadedFolder: String?
}

extension LoadableView: ActionUIAdwaitaRenderer {
    /// viewDidLoadActionID once per source, for every LoadableView on GTK.
    private static let viewDidLoad = ActionUIDocumentLoader.ViewDidLoad()

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = ZStackLayout.makeStack()
        attach(LoadableState(), to: widget, key: loadableStateKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: loadableStateKey) else { return }
        let value = initialValue(node.model) as? String ?? ""
        if value != state.source {
            state.source = value
            load(value, widget, node, state)
        }
        syncContainerChildren(node, widget, state.element.map { [$0] } ?? [])
    }

    private static func load(_ value: String, _ widget: WidgetPointer, _ node: RenderNode, _ state: LoadableState) {
        let logger = ActionUIModel.shared.logger
        state.generation &+= 1
        state.element = nil
        state.loadedFolder = nil
        guard !value.isEmpty else {
            logger.log("No valid source for LoadableView, displaying error text", .warning)
            return showStatus(message("No valid source provided", error: false), widget, state)
        }
        let documentFolder = documentFolder(of: node)
        let source = ActionUIDocumentLoader.source(for: value, bundleURL: { name, ext in
            let file = "\(name).\(ext)"
            return (AppBundle.file(file, in: documentFolder) ?? AppBundle.resource(file)).map { URL(fileURLWithPath: $0) }
        }, logger: logger)
        let windowUUID = node.windowUUID
        let parentID = node.element.id
        let actionID = Props(node.properties).viewDidLoadActionID
        switch source {
        case .failure(let error):
            showStatus(message(error.message, error: false), widget, state)
        case .success(.file(let url)):
            let format = ActionUIDocumentLoader.format(of: url)
            do {
                let data = try Data(contentsOf: url)
                state.element = try ActionUIDocumentLoader.load(data: data, format: format, windowUUID: windowUUID,
                                                               isContentView: false, parentID: parentID)
                state.loadedFolder = url.deletingLastPathComponent().path
                logger.log("Successfully loaded \(format) for LoadableView from \(url.absoluteString)", .debug)
                showStatus(nil, widget, state)
                // After this sync, as SwiftUI fires it after the body that loaded.
                let fired = url.absoluteString
                _ = runAfter(milliseconds: 0) {
                    viewDidLoad.fire(source: fired, windowUUID: windowUUID, parentID: parentID, actionID: actionID)
                }
            } catch {
                logger.log("Failed to load description for LoadableView from \(url.absoluteString): \(error)", .error)
                showStatus(message("Failed to load view: \(failureText(error, url))", error: true), widget, state)
            }
        case .success(.remote(let url)):
            let spinner = adw_spinner_new()!
            showStatus(spinner, widget, state)
            let generation = state.generation
            Task { @MainActor [weak node, weak state] in
                // Still this LoadableView's current load: one that a newer source or removal made
                // stale must not load into the window, which would drop the newer sub-view's models.
                let isCurrent = { node?.isAttached == true && state?.generation == generation }
                let result: Result<ActionUIElement, Error>
                do {
                    result = .success(try await ActionUIDocumentLoader.loadRemote(
                        url: url, windowUUID: windowUUID, isContentView: false, parentID: parentID, logger: logger,
                        fetch: { url in
                            let data = try await URLLoader.data(url)
                            guard isCurrent() else { throw CancellationError() }
                            return data
                        }))
                } catch {
                    result = .failure(error)
                }
                guard isCurrent(), let node, let state, let widget = node.widget else { return }
                switch result {
                case .success(let element):
                    state.element = element
                    showStatus(nil, widget, state)
                    viewDidLoad.fire(source: url.absoluteString, windowUUID: windowUUID, parentID: parentID, actionID: actionID)
                case .failure(let error):
                    logger.log("Failed to load remote description for LoadableView from \(url.absoluteString): \(error)", .error)
                    showStatus(message("Failed to load view: \(failureText(error, url))", error: true), widget, state)
                }
                SyncScheduler.shared.markDirty(node)
            }
        }
    }

    /// Why a load failed, in the words Apple's localizedDescription uses for the common cases (a
    /// file that is missing or unreadable, a description that does not parse).
    static func failureText(_ error: any Error, _ url: URL) -> String {
        let name = url.lastPathComponent
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileReadNoSuchFile, .fileNoSuchFile:
                return "The file \"\(name)\" couldn't be opened because there is no such file."
            case .fileReadNoPermission:
                return "The file \"\(name)\" couldn't be opened because you don't have permission to view it."
            default:
                return "The file \"\(name)\" couldn't be opened."
            }
        }
        if error is DecodingError {
            return "The data couldn't be read because it isn't in the correct format."
        }
        return "\(error)"
    }

    /// Puts `status` in the LoadableView in place of the one it had (nil: none).
    private static func showStatus(_ status: WidgetPointer?, _ widget: WidgetPointer, _ state: LoadableState) {
        if let old = state.status {
            gtk_widget_unparent(old)
        }
        state.status = status
        if let status {
            gtk_widget_set_parent(status, widget)
        }
    }

    /// A message in the LoadableView's place, wrapped; in the error color for a load that failed, as
    /// SwiftUI shows it in red.
    private static func message(_ text: String, error: Bool) -> WidgetPointer {
        let label = gtk_label_new(text)!
        gtk_label_set_wrap(opaque(label), 1)
        Gtk.Widget(label).setCSSClass("error", error)
        return label
    }
}

extension LoadableView {
    /// The folder of the document holding `node`: the file the nearest enclosing LoadableView
    /// loaded, else the window's document's folder.
    fileprivate static func documentFolder(of node: RenderNode) -> String? {
        var ancestor = node.parent
        while let current = ancestor {
            if let widget = current.widget, let state = attached(on: widget, key: loadableStateKey) {
                return state.loadedFolder
            }
            ancestor = current.parent
        }
        return AppBundle.documentFolder(window: node.windowUUID)
    }
}
