// Sources/Runtime/NodeHover+WinUI.swift
/*
 onHoverActionID on WinUI: the pointer entering the element's frame fires it with
 {"isHovering": true}, leaving it with {"isHovering": false}, as SwiftUI's onHover does on macOS and
 NodeHover does on Linux. The action fires on the main queue's next turn (AreaPresence; Apple uses a
 Task), with the element's id. Tracked: the box's group, which is exactly the frame (padding and
 background included, moved by offset, rotation and scale), the area SwiftUI's hover tracks, all of
 it (an empty group gets a transparent background, so a click on its empty padding no longer
 reaches what is behind it); and the element's overlay view, which SwiftUI's hover covers too: the
 pointer moving between them reports nothing. A finger does not hover (as on Apple). Only an
 element declaring onHoverActionID when its node is made is watched.
*/

import CWinUI

@MainActor
enum NodeHover {
    /// Watches the pointer over `node`'s frame and its overlay view when its element declares
    /// onHoverActionID. Called while the node is made, which may be in its parent's sync: the read
    /// is untracked.
    static func watch(_ node: RenderNode) {
        let declares = UntrackedReads.perform {
            ActionUIRegistry.shared.currentProperties(element: node.element, model: node.model)["onHoverActionID"] is String
        }
        guard declares else { return }
        let presence = AreaPresence { [weak node] hovering in
            guard let node, node.isAttached,
                  // Untracked: the pointer can cross during another node's sync.
                  let actionID = UntrackedReads.perform({ BaseModifiers(node.properties).onHoverActionID }),
                  !actionID.isEmpty else { return }
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id,
                                               viewPartID: 0, context: ["isHovering": hovering])
        }
        var areas: [WinUIObject] = []
        if let box = node.box {
            // Kept when the box paints the group or rounds it later (the shim's clear background
            // only covers the group as it is now).
            box.keepsGroupHitArea = true
            areas.append(box.group.object)
            if let overlay = box.overlayObject {
                areas.append(overlay)
            }
        } else if let view = node.view {
            areas.append(view)
        }
        for (index, area) in areas.enumerated() {
            WinUIEvents.connect(area, actionUIWinUIElementOnPointerEntered, "a hover's entering") {
                presence.entered(index)
            }
            WinUIEvents.connect(area, actionUIWinUIElementOnPointerExited, "a hover's leaving") {
                presence.left(index)
            }
        }
    }
}
