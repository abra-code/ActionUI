// Sources/Runtime/NodeAppearance.swift
/*
 onAppearActionID and onDisappearActionID on GTK: the element's box being mapped (shown on
 screen: the window showing it, its page or tab coming back, its container showing it again) fires
 onAppearActionID, and its being unmapped (hidden, its page or tab left, taken out of the tree, its
 window closed) fires onDisappearActionID, as SwiftUI's onAppear and onDisappear fire, each time.
 As on Apple, the action fires on the main queue's next turn (Apple uses a Task), with the element's
 id and no context; a view that is merely hidden (transparent) stays mapped, as a hidden SwiftUI
 view stays in the hierarchy.

 Only an element that declares either action when its node is made is watched.
*/

import CAdwaita
import Dispatch

@MainActor
enum NodeAppearance {
    /// Watches `node`'s box when its element declares onAppearActionID or onDisappearActionID. Called
    /// while the node is made, which may be in its parent's sync: the read is untracked. Returns
    /// whether it watches.
    static func watch(_ node: RenderNode) -> Bool {
        let declares = UntrackedReads.perform {
            let properties = ActionUIRegistry.shared.currentProperties(element: node.element, model: node.model)
            return properties["onAppearActionID"] is String || properties["onDisappearActionID"] is String
        }
        guard declares else { return false }
        let box = UnsafeMutableRawPointer(node.outerWidget!)
        // A node out of the tree reported its disappearance when it left (left(_:)).
        connectSignal(box, "map", .instanceOnly) { [weak node] in
            guard let node, node.isAttached else { return }
            fire(node, appearing: true)
        }
        connectSignal(box, "unmap", .instanceOnly) { [weak node] in
            guard let node, node.isAttached else { return }
            fire(node, appearing: false)
        }
        return true
    }

    /// A watched node leaving the tree (detach) while its box is still on screen disappears now:
    /// its window closing, or a row dropped before its box is taken out. Nothing may hold the node
    /// by the time GTK unmaps the box.
    static func left(_ node: RenderNode) {
        guard gtk_widget_get_mapped(node.outerWidget) != 0 else { return }
        fire(node, appearing: false)
    }

    private static func fire(_ node: RenderNode, appearing: Bool) {
        // Untracked: a map can come during another node's sync.
        let modifiers = UntrackedReads.perform { BaseModifiers(node.properties) }
        guard let actionID = appearing ? modifiers.onAppearActionID : modifiers.onDisappearActionID else { return }
        // The node held until then: one leaving the tree still reports that it disappeared.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                node.fire(actionID)
            }
        }
    }
}
