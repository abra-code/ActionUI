// Sources/Runtime/WinUIElement.swift
/*
 What an add-on library implements for an element type on Windows, as on Linux
 (ActionUIAdwaitaElement) and Apple (ActionUIViewConstruction): the element's spec
 (ActionUIElementSpec, shared with the other platforms) with the calls that draw it.
 ActionUIRegistry.register(_:as:) binds it to a JSON type token.

 The built-in renderers' protocol (ActionUIWinUIRenderer) stays internal, so its hooks can change
 with the renderer; a registered element goes through the adapter below. WinUI objects cross this
 boundary as the shim's `ActionUIWinUIObject *` (an OpaquePointer in Swift), which an add-on makes
 and changes with the shim's C functions (CWinUI).
*/

import CWinUI
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
public protocol ActionUIWinUIElement: ActionUIElementSpec {
    /// Creates the element's WinUI object, once per element instance, and returns a reference of
    /// the caller's own (what the shim's create functions return), never a pointer the shim lends:
    /// the node takes it over and releases it. Returns
    /// nil when the object could not be made; the node then shows a placeholder and logs the shim's
    /// last error. Reads nothing from the model: what it read would count as read by the parent,
    /// and `update` runs right after. A closure handed to the shim or kept by the element captures
    /// the node weakly: a node keeps its window's data alive while something holds it.
    static func makeView(_ node: RenderNode) -> OpaquePointer?

    /// Makes the object show the model. Runs after makeView and again whenever a value, state or
    /// property it read changes, or after `node.setNeedsUpdate()`. Idempotent. Never writes the
    /// model and never fires actions. `view` is lent for the call.
    static func update(_ view: OpaquePointer, _ node: RenderNode)

    /// How the element grows when its container offers more room than it asks for. Read when the
    /// node is made and during its sync, tracked. Default: none, it keeps the size it asks for.
    static func expansion(_ node: RenderNode) -> ActionUIExpansion

    /// The axes along which a stack may make the element smaller than it asks for (a text that
    /// wraps). Read as `expansion` is. Default: none.
    static func compression(_ node: RenderNode) -> ActionUIExpansion
}

extension ActionUIWinUIElement {
    public static func expansion(_ node: RenderNode) -> ActionUIExpansion { [] }

    public static func compression(_ node: RenderNode) -> ActionUIExpansion { [] }
}

extension RenderNode {
    /// The UUID of the window the element is in.
    public var windowUUID: String { windowModel.windowUUID }

    /// Syncs the node again soon, for a change the model cannot report: an image an add-on's element
    /// asked for has arrived. Does nothing once the node has left the tree, so what holds the node
    /// may call it after the window closed.
    public func setNeedsUpdate() {
        SyncScheduler.shared.markDirty(self)
    }

    /// Whether this node's content may read the local file at `path`, as the built-in elements that
    /// read files decide (LinkTrust.readsLocalFile): for add-on elements that read files. Less-trusted
    /// content reads no network or device path (\\server\share and the like), whatever the trust
    /// policy says. Ask before touching the path in any way (even a test whether it exists reaches a
    /// share's server with the user's credentials), with the path exactly as it will be opened: a
    /// relative path resolved first, from its text alone. URL(filePath:directoryHint: .notDirectory)
    /// touches nothing; URL(fileURLWithPath:) opens the path to learn whether it is a folder.
    public func readsLocalFile(_ path: String) -> Bool {
        LinkTrust.readsLocalFile(path, self)
    }

    /// Whether this node's content may read the file the file: URL `url` names, as readsLocalFile
    /// decides for its path. Ask this, not readsLocalFile(url.path), before handing a file: URL to
    /// anything that opens it: `url.path` drops the host, so "file://server/share/a.png" would be
    /// asked about "/share/a.png" while Windows opens \\server\share\a.png. False for a URL that is
    /// not a file: URL.
    public func readsFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return LinkTrust.readsLocalFile(LinkTrust.filePath(of: url), self)
    }

    /// Opens `url` as a Link does, when this node's content may (the trust policy's openLink, refused
    /// and logged otherwise): the URL the policy was asked about, as Foundation writes it, so Windows
    /// opens that address (LinkTrust.judgedText). True when it opened. For add-on elements with links
    /// (a RichText's), after their own checks of the URL.
    @discardableResult
    public func openLink(_ url: String) -> Bool {
        guard let judged = LinkTrust.judgedText(url, self) else { return false }
        let logger = ActionUIModel.shared.logger
        logger.log("element \(element.id): opening \(judged)", .debug)
        guard URLLauncher.launch(judged) else {
            logger.log("element \(element.id): \(WinUIError.last("opening \(judged)")); it opens nothing", .warning)
            return false
        }
        return true
    }

    /// Whether this node's content may do `capability`, with a refusal logged once per element
    /// (ActionUIModel.allowsLoggingOnce; `what` names it in the log): for add-on elements.
    public func allowsLoggingOnce(_ capability: ActionUICapability, what: String) -> Bool {
        LinkTrust.allowsLoggingOnce(capability, what: what, self)
    }
}

/// A registered element in the built-in renderers' place.
private enum AddOnRenderer<Element: ActionUIWinUIElement>: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let view = WinUIObject(adopting: Element.makeView(node)) else {
            throw WinUIError.last("creating the element \(node.element.type)")
        }
        return view
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        Element.update(view.pointer, node)
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        Element.expansion(node)
    }

    static func compression(_ node: RenderNode) -> Expansion {
        Element.compression(node)
    }
}

extension ActionUIRegistry {
    /// Registers an add-on's element type, so its `type` token can be used in ActionUI JSON exactly
    /// like a built-in element. An add-on exposes a small `register()` that the host calls at launch,
    /// before any window that uses the element is built. A later call for the same token replaces
    /// the earlier type for the elements built after it; those already shown keep theirs.
    ///
    /// - Parameters:
    ///   - type: a type conforming to ``ActionUIWinUIElement``.
    ///   - typeName: the JSON `type` token to bind. Defaults to the Swift type's own name.
    public func register(_ type: any ActionUIWinUIElement.Type, as typeName: String? = nil) {
        let key = typeName ?? String(describing: type)
        specs[key] = type
        setWinUIRenderer(adapter(for: type), forElementType: key)
        logger.log("Registered custom view type: \(key)", .verbose)
    }

    private func adapter<Element: ActionUIWinUIElement>(for type: Element.Type) -> any ActionUIWinUIRenderer.Type {
        AddOnRenderer<Element>.self
    }
}
