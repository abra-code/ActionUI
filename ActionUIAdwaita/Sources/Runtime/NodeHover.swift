// Sources/Runtime/NodeHover.swift
/*
 onHoverActionID on GTK: the pointer entering the element's frame fires it with
 {"isHovering": true}, leaving it with {"isHovering": false}, as SwiftUI's onHover does on macOS.
 As on Apple, the action fires on the main queue's next turn (Apple uses a Task), with the
 element's id. The controller is on the box's content group, which is exactly the frame (padding
 and background included, moved by offset, rotation and scale), the area SwiftUI's hover tracks;
 the box itself can be given more (a window's root fills the window). It is on the element's
 overlay view too, which SwiftUI's hover covers: the pointer moving between them reports nothing.
 Only an element declaring onHoverActionID when its node is made is watched.
*/

import CAdwaita

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
                  let actionID = UntrackedReads.perform({ BaseModifiers(node.properties).onHoverActionID }) else { return }
            node.fire(actionID, context: ["isHovering": hovering])
        }
        for (index, area) in NodeDecorations.pointerAreas(node).enumerated() {
            let motion = gtk_event_controller_motion_new()!
            connectPoint(UnsafeMutableRawPointer(motion), "enter") { _, _ in
                presence.entered(index)
            }
            connectSignal(UnsafeMutableRawPointer(motion), "leave", .instanceOnly) {
                presence.left(index)
            }
            gtk_widget_add_controller(area, motion)
        }
    }
}
