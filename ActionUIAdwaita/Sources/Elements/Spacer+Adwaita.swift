// Sources/Elements/Spacer+Adwaita.swift
/*
 Spacer on GTK: an empty widget that expands along its parent stack's axis (in both axes outside
 a stack), at least minLength long in that axis (8, SwiftUI's usual spacing, when not given), as
 SwiftUI's Spacer(minLength:) is.
*/

import CAdwaita

extension Spacer: ActionUIAdwaitaRenderer {
    static let defaultMinLength = 8.0

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        // Its stack places it after the other children and puts no default spacing next to it.
        attach(SpacerMarker(), to: widget, key: spacerMarkerKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let length = Int32(StackSolver.length(props.minLength ?? defaultMinLength))
        let axis = parentAxis(node)
        let horizontal = axis != .vertical
        let vertical = axis != .horizontal
        gtk_widget_set_size_request(widget, horizontal ? length : -1, vertical ? length : -1)
        gtk_widget_set_hexpand(widget, horizontal ? 1 : 0)
        gtk_widget_set_vexpand(widget, vertical ? 1 : 0)
    }

    /// The axis of the stack the spacer is in; nil outside a stack.
    static func parentAxis(_ node: RenderNode) -> StackAxis? {
        switch node.parent?.element.type {
        case "VStack", "LazyVStack": return .vertical
        case "HStack", "LazyHStack": return .horizontal
        default: return nil
        }
    }
}
