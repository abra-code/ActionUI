// Sources/Elements/Spacer+Adwaita.swift
/*
 Spacer on GTK: an empty widget that expands along its parent stack's axis (vertically in a
 GroupBox, whose content is a vertical stack, horizontally in LabeledContent's row; in both axes
 outside a stack), at least minLength long in that axis (8, SwiftUI's usual spacing, when not
 given), as SwiftUI's Spacer(minLength:) is.
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

    /// The axis of the stack the element is in (from its parent element's type); nil outside a stack
    /// (also for a background or overlay view, which is not in its element's stack).
    /// In a Group or Section, its stack's (Group+Adwaita); one that no stack lays out is a VStack.
    /// Divider uses it too.
    static func parentAxis(_ node: RenderNode) -> StackAxis? {
        guard node.decoration == nil else { return nil }
        switch node.parent?.element.type {
        case "VStack", "LazyVStack", "GroupBox", "Form": return .vertical
        case "HStack", "LazyHStack", "LabeledContent": return .horizontal
        case "Group", "Section":
            guard let group = node.parent, Group.isFlattened(group.widget) else { return .vertical }
            return parentAxis(group)
        default: return nil
        }
    }
}
