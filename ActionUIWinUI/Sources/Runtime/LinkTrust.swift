// Sources/Runtime/LinkTrust.swift
/*
 What a part of a window may do by the host's trust policy (ActionUIModel.allows), as on Linux
 (LinkTrust.swift there): Link asks it before opening an address. The element asked about is the
 node's own; a template row's elements are blueprints with view models of their own, not the
 window's, and take their container's origin. A node whose view model is not the window's one for
 its id (a template's id that matches another element's, a node about to be replaced) counts as less
 trusted.

 The app's own resources, whose ActionUI JSON is trusted: the folder the host names
 (ActionUIResourceFolder), else the running program's folder, which an installed Windows app's
 files ship in (resourceFolders).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

@MainActor
enum LinkTrust {
    /// Whether the node's content may open `uri`; a refusal is logged. An address that does not
    /// parse opens only from trusted content.
    static func allows(_ uri: String, _ node: RenderNode) -> Bool {
        let viewID = originElementID(node)
        let windowUUID = node.windowModel.windowUUID
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
        return ActionUIModel.shared.allows(capability, windowUUID: node.windowModel.windowUUID, viewID: viewID)
    }

    /// Whether the node's content may do `capability`, with a refusal logged once per element
    /// (ActionUIModel.allowsLoggingOnce); for checks made each time a node syncs.
    static func allowsLoggingOnce(_ capability: ActionUICapability, what: String, _ node: RenderNode) -> Bool {
        if let viewID = originElementID(node) {
            return ActionUIModel.shared.allowsLoggingOnce(capability, what: what, windowUUID: node.windowModel.windowUUID, viewID: viewID)
        }
        return ActionUIModel.shared.trustPolicy.allows(capability, for: unknownOrigin)
    }

    /// Whether the node's content is trusted: its element's origin (or its template row's
    /// container's) is; content whose element cannot be told is not.
    static func isTrusted(_ node: RenderNode) -> Bool {
        guard let viewID = originElementID(node) else { return false }
        return ActionUIModel.shared.origin(windowUUID: node.windowModel.windowUUID, viewID: viewID)?.trust == .trusted
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
    private static let unknownOrigin = JSONContentOrigin(source: .host, trust: .lessTrusted, parentID: nil)

    // MARK: The app's resources

    /// The folders of the app's own resources (ActionUIRendererHooks.resourceFolders): the host's
    /// (ActionUIResourceFolder), else the running program's; none when neither is known.
    static func resourceFolders() -> [String] {
        if let host = ActionUIResourceFolder.path {
            return [host]
        }
        return programFolder.map { [$0] } ?? []
    }

    /// The folder of the running program (nil only when Windows cannot tell it).
    private static let programFolder: String? = {
        guard let copy = actionUIWinUICopyProgramFolder() else {
            ActionUIModel.shared.logger.log("LinkTrust: \(WinUIError.last("finding the program's folder")); only the host's resource folder is trusted", .warning)
            return nil
        }
        defer { actionUIWinUIFreeString(copy) }
        return String(cString: copy)
    }()
}
