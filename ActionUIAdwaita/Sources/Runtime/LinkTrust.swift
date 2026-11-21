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

    /// The origin of content whose element cannot be told: less trusted, as ActionUIModel.allows
    /// treats an element with no view model.
    private static let unknownOrigin = DocumentOrigin(source: .host, trust: .lessTrusted, parentID: nil)
}
