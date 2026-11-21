// Sources/Runtime/NodeAppearance+WinUI.swift
/*
 onAppearActionID and onDisappearActionID on WinUI: the element's box entering a window (WinUI's
 Loaded: the window showing it, its tab or page coming back) fires onAppearActionID, and its leaving
 (Unloaded: its tab or page left, taken out of the tree, its window closing) fires
 onDisappearActionID, as SwiftUI's onAppear and onDisappear fire, each time, and as the Linux
 renderer's NodeAppearance does on its box's map and unmap. As on Apple, the action fires on the main
 queue's next turn, with the element's id and no context; a view that is merely hidden (transparent)
 stays, as a hidden SwiftUI view stays in the hierarchy.

 WinUI raises Unloaded after the removal, so a box removed and added back at once (a stack re-adding
 its children when a sibling changes) gets a stale Unloaded while it is in the window again, before
 or after its new Loaded (both are queued, in no fixed order, and the box's own IsLoaded reads false
 until its Loaded is raised): the node keeps whether it appeared, appears only when it had not, and
 disappears only when its box is out of the window (no element it is in is loaded).

 Only an element that declares either action when its node is made is watched. Not yet: a box
 collapsed in place (a closed DisclosureGroup's content) stays loaded on WinUI, so it does not
 disappear, where GTK unmaps it.
*/

import CWinUI
import Dispatch

/// Whether a watched node's box appeared, kept by the node.
@MainActor
final class AppearanceWatch {
    var appeared = false
}

@MainActor
enum NodeAppearance {
    /// Watches `node`'s box when its element declares onAppearActionID or onDisappearActionID. Called
    /// while the node is made: the read is untracked. Nil when it does not watch.
    static func watch(_ node: RenderNode) -> AppearanceWatch? {
        let declares = UntrackedReads.perform {
            node.properties["onAppearActionID"] is String || node.properties["onDisappearActionID"] is String
        }
        guard declares, let box = node.outerView else { return nil }
        let watch = AppearanceWatch()
        WinUIEvents.connect(box, actionUIWinUIElementOnLoaded, "an element's appearing") { [weak node, weak watch] in
            guard let node, let watch, node.isAttached, !watch.appeared else { return }
            watch.appeared = true
            fire(node, appearing: true)
        }
        WinUIEvents.connect(box, actionUIWinUIElementOnUnloaded, "an element's disappearing") { [weak node, weak watch, weak box] in
            guard let node, let watch, let box, node.isAttached, watch.appeared,
                  !actionUIWinUIElementIsInWindow(box.pointer) else { return }
            watch.appeared = false
            fire(node, appearing: false)
        }
        return watch
    }

    /// A watched node leaving the tree (detach) while its box is shown disappears now: its window
    /// closing, or a row dropped before its box is taken out.
    static func left(_ node: RenderNode, _ watch: AppearanceWatch) {
        guard watch.appeared else { return }
        watch.appeared = false
        fire(node, appearing: false)
    }

    private static func fire(_ node: RenderNode, appearing: Bool) {
        // Untracked: a Loaded can come during another node's sync.
        let modifiers = UntrackedReads.perform { BaseModifiers(node.properties) }
        guard let actionID = appearing ? modifiers.onAppearActionID : modifiers.onDisappearActionID else { return }
        let windowUUID = node.windowModel.windowUUID
        let viewID = node.element.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0)
            }
        }
    }
}
