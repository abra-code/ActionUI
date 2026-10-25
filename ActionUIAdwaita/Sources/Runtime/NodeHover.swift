// Sources/Runtime/NodeHover.swift
/*
 onHoverActionID on GTK: the pointer entering the element's frame fires it with
 {"isHovering": true}, leaving it with {"isHovering": false}, as SwiftUI's onHover does on macOS.
 As on Apple, the action fires on the main queue's next turn (Apple uses a Task), with the
 element's id. The controller is on the box's content group, which is exactly the frame (padding
 and background included, moved by offset, rotation and scale), the area SwiftUI's hover tracks;
 the box itself can be given more (a window's root fills the window). Only an element declaring
 onHoverActionID when its node is made is watched.
*/

import CAdwaita
import Dispatch

@MainActor
enum NodeHover {
    /// Watches the pointer over `node`'s frame when its element declares onHoverActionID. Called
    /// while the node is made, which may be in its parent's sync: the read is untracked.
    static func watch(_ node: RenderNode) {
        let declares = UntrackedReads.perform {
            ActionUIRegistry.shared.currentProperties(element: node.element, model: node.model)["onHoverActionID"] is String
        }
        guard declares else { return }
        let motion = gtk_event_controller_motion_new()!
        connectPoint(UnsafeMutableRawPointer(motion), "enter") { [weak node] _, _ in
            fire(node, hovering: true)
        }
        connectSignal(UnsafeMutableRawPointer(motion), "leave", .instanceOnly) { [weak node] in
            fire(node, hovering: false)
        }
        gtk_widget_add_controller(ModifierBox.content(of: node.outerWidget), motion)
    }

    private static func fire(_ node: RenderNode?, hovering: Bool) {
        guard let node, node.isAttached else { return }
        // Untracked: the pointer can cross during another node's sync.
        guard let actionID = UntrackedReads.perform({ BaseModifiers(node.properties).onHoverActionID }) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                node.fire(actionID, context: ["isHovering": hovering])
            }
        }
    }
}
