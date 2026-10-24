// Sources/Runtime/ContainerTap.swift
/*
 A VStack, HStack or ZStack carrying an actionID is tappable as a whole on GTK, as on Apple (Core
 ContainerAction decides which and what it dispatches): a click anywhere in the element's box,
 frame, padding and background included, fires the action, with the template row's container id
 and row index inside a template row, else its own id and 0.

 - The click gesture is on the box in the bubble phase, so a control inside the cell (a Button, a
   toggle) handles its own click first and, claiming it, cancels the cell's: the innermost action
   wins, as in SwiftUI.
 - The cell claims every click pressed in it, as a GtkButton does, so an enclosing container's tap
   and an enclosing List row's selection do not happen as well.
 - A click is a press and release inside the box; one dragged out of it does nothing, in the cell
   or in an enclosing tappable container.
 - A disabled container does nothing (Core resolves no dispatch), nor one inside a disabled
   ancestor (GTK gives an insensitive widget no events).
*/

import CAdwaita

@MainActor
enum ContainerTap {
    /// The tap installed on a box, with the dispatch it fires.
    final class Installed {
        let gesture: OpaquePointer
        var dispatch: ContainerAction.Dispatch

        init(gesture: OpaquePointer, dispatch: ContainerAction.Dispatch) {
            self.gesture = gesture
            self.dispatch = dispatch
        }
    }

    static let installedKey = AttachKey<Installed>("actionui-container-tap")

    /// Makes `box` (a node's ModifierBox) fire the container's action on a click, or takes the
    /// tap away when the element dispatches none.
    static func apply(_ node: RenderNode, box: WidgetPointer) {
        let dispatch = ContainerAction.resolve(element: node.element, properties: node.properties,
                                               templateContext: node.model.templateContext)
        let installed = attached(on: UnsafeMutableRawPointer(box), key: installedKey)
        guard let dispatch else {
            if let installed {
                gtk_widget_remove_controller(box, installed.gesture)
                g_object_set_data(typed(OpaquePointer(box)), installedKey.name, nil)
            }
            return
        }
        if let installed {
            installed.dispatch = dispatch
            return
        }
        let gesture = gtk_gesture_click_new()!
        let record = Installed(gesture: gesture, dispatch: dispatch)
        connectClick(UnsafeMutableRawPointer(gesture), "released") { [weak node, weak record] _, x, y in
            guard let node, let record else { return }
            // Claimed wherever it is released, as a GtkButton claims its click: a press dragged
            // out of an inner cell would otherwise reach an enclosing tappable container, which
            // would fire for a release inside its own box.
            gtk_gesture_set_state(record.gesture, GTK_EVENT_SEQUENCE_CLAIMED)
            // Released inside the box: a click, not a drag out of it.
            guard x >= 0, y >= 0, x < Double(gtk_widget_get_width(box)), y < Double(gtk_widget_get_height(box)) else { return }
            ActionUIModel.shared.actionHandler(record.dispatch.actionID, windowUUID: node.windowUUID,
                                               viewID: record.dispatch.viewID, viewPartID: record.dispatch.viewPartID)
        }
        gtk_widget_add_controller(box, gesture)
        attach(record, to: UnsafeMutableRawPointer(box), key: installedKey)
    }
}
