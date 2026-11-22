// Sources/Runtime/LinkTrust.swift
/*
 Whether a link in a part of a window may open its address, by the trust policy
 (ActionUIModel.allows, .openLink): Link, links in Text, and links in a markdown TextEditor ask it
 before opening. The element asked about is the node's own; a template row's elements are
 blueprints with view models of their own, not the window's, and take their container's origin. A
 node whose view model is not the window's one for its id (a template's id that matches another
 element's, a node about to be replaced) counts as less trusted.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
enum LinkTrust {
    /// Whether the node's content may open `uri`; a refusal is logged. An address that does not
    /// parse opens only from trusted content.
    static func allows(_ uri: String, _ node: RenderNode) -> Bool {
        let viewID = originElementID(node)
        let windowUUID = node.windowUUID
        let allowed: Bool
        if let url = URL(string: uri) {
            if let viewID {
                allowed = ActionUIModel.shared.allows(.openLink(url), windowUUID: windowUUID, viewID: viewID)
            } else {
                allowed = ActionUIModel.shared.trustPolicy.allows(.openLink(url), for: unknownOrigin)
            }
        } else {
            allowed = viewID.flatMap { ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: $0) }?.trust == .trusted
        }
        if !allowed {
            ActionUIModel.shared.logger.log("Not opening \(uri) from element \(viewID ?? node.element.id) of window \(windowUUID): the trust policy refuses it", .warning)
        }
        return allowed
    }

    /// Whether the node's content may do `capability` (not logged): asked for its element, or as
    /// content of unknown origin when its element cannot be told (originElementID).
    static func allows(_ capability: ActionUICapability, _ node: RenderNode) -> Bool {
        guard let viewID = originElementID(node) else {
            return ActionUIModel.shared.trustPolicy.allows(capability, for: unknownOrigin)
        }
        return ActionUIModel.shared.allows(capability, windowUUID: node.windowUUID, viewID: viewID)
    }

    /// Whether the node's content may do `capability`, with a refusal logged once per element
    /// (ActionUIModel.allowsLoggingOnce); for checks made each time a node syncs.
    static func allowsLoggingOnce(_ capability: ActionUICapability, what: String, _ node: RenderNode) -> Bool {
        if let viewID = originElementID(node) {
            return ActionUIModel.shared.allowsLoggingOnce(capability, what: what, windowUUID: node.windowUUID, viewID: viewID)
        }
        return ActionUIModel.shared.trustPolicy.allows(capability, for: unknownOrigin)
    }

    /// Whether the node's content may read the local file at `path` (an image, a canvas image, a
    /// video): trusted content reads anything without asking; other content asks the trust policy
    /// (.readLocalFile), and a refusal is logged. Without a node, the content's origin is unknown.
    static func readsLocalFile(_ path: String, _ node: RenderNode?) -> Bool {
        reads(.readLocalFile(path), path: path, node)
    }

    /// Whether the node's content is trusted: its element's origin (or its template row's
    /// container's) is; content whose element cannot be told is not.
    static func isTrusted(_ node: RenderNode) -> Bool {
        guard let viewID = originElementID(node) else { return false }
        return ActionUIModel.shared.origin(windowUUID: node.windowUUID, viewID: viewID)?.trust == .trusted
    }

    /// Whether the node's content may do `capability`, a read of the file at `path`, as
    /// readsLocalFile decides (for a WebView script file, .webViewScriptFile).
    static func reads(_ capability: ActionUICapability, path: String, _ node: RenderNode?) -> Bool {
        if let node, isTrusted(node) {
            return true
        }
        let allowed = node.map { allows(capability, $0) }
            ?? ActionUIModel.shared.trustPolicy.allows(capability, for: unknownOrigin)
        if !allowed {
            ActionUIModel.shared.logger.log("Not reading \(path) for element \(node.map { String($0.element.id) } ?? "?"): the trust policy refuses it", .warning)
        }
        return allowed
    }

    /// The id of the element whose origin the node's content has: the node's own, or for a template
    /// row's node the nearest container around it; nil when that node's view model is not the
    /// window's one for its id, so the id would name another element's origin.
    static func originElementID(_ node: RenderNode) -> Int? {
        var current = node
        while current.model.templateContext != nil, let parent = current.parent {
            current = parent
        }
        guard current.windowModel.viewModels[current.element.id] === current.model else { return nil }
        return current.element.id
    }

    /// The origin the node's actions are judged by: its element's, or for a template row's node the
    /// container's around it (originElementID); less trusted when the element cannot be told. A
    /// template element may carry any id its JSON gives it, a trusted element's among them, so its
    /// own id must not decide.
    static func origin(_ node: RenderNode) -> JSONContentOrigin {
        originElementID(node).flatMap { ActionUIModel.shared.origin(windowUUID: node.windowUUID, viewID: $0) } ?? unknownOrigin
    }

    /// The origin of content whose element cannot be told: less trusted, as ActionUIModel.allows
    /// treats an element with no view model.
    private static let unknownOrigin = JSONContentOrigin(source: .host, trust: .lessTrusted, parentID: nil)
}

extension RenderNode {
    /// Whether this node's content may read the local file at `path`, as the built-in elements that
    /// read files decide (LinkTrust.readsLocalFile): for add-on elements that read files.
    public func readsLocalFile(_ path: String) -> Bool {
        LinkTrust.readsLocalFile(path, self)
    }
}
