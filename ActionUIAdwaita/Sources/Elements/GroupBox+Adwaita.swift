// Sources/Elements/GroupBox+Adwaita.swift
/*
 GroupBox on GTK: its children in a libadwaita card, under its title when it has one, as macOS
 puts a GroupBox's title above its box. Measured on macOS 27 (the layout parity fixtures): the
 content is inset 5 points on every side, the children are centered and 8 points apart, none next
 to a Spacer (where a VStack of the same views puts none at all), and the box is as large as its children unless one of them
 fills. A title puts the box 17 points lower; here the title label and a 4 px gap do.

 The element widget is a group for assistive technologies, named after the title, which is read once
 (the visible title label has the presentation role).

 Not yet: the template form (rows from setElementRows) shows no rows; logged once.
*/

import CAdwaita

@MainActor private var reportedTemplate = false

/// Attached to a GroupBox's widget: LayoutCaps finds how far the GroupBox expands through it.
@MainActor
final class GroupBoxMarker {}

let groupBoxMarkerKey = AttachKey<GroupBoxMarker>("actionui-groupbox")

extension GroupBox: ActionUIAdwaitaRenderer {
    /// The content's inset on every side, measured on macOS 27.
    static let contentPadding = 5
    /// The gap between the title and the box.
    static let titleSpacing: Int32 = 4

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let group = groupBox()
        // Left out of the accessibility tree: the group carries the title as its name.
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_label_set_xalign(opaque(title), 0)
        Gtk.Widget(title).isVisible = false
        gtk_box_append(typed(group), title)
        let content = StackLayout.makeStack(axis: .vertical)
        Gtk.Widget(content).setCSSClass("card", true)
        StyleSheet.shared.apply(["padding: \(contentPadding)px;"], to: content, slot: "groupBoxPadding")
        // SwiftUI's default spacing: 8 points between the children, none next to a Spacer (measured
        // on macOS 27).
        StackLayout.configure(content, spacing: nil, alignment: .center)
        gtk_box_append(typed(group), content)
        attach(GroupBoxMarker(), to: group, key: groupBoxMarkerKey)
        return group
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let title = Gtk.Widget(widget).firstChild?.pointer, let content = Gtk.Widget(widget).lastChild?.pointer else { return }
        let text = Props(node.properties).title ?? ""
        Gtk.Label(title).text = text
        Gtk.Widget(title).isVisible = !text.isEmpty
        syncContainerChildren(node, content, node.subviews("children"))
        if !reportedTemplate, node.effectiveElement.subviews?["template"] != nil {
            reportedTemplate = true
            ActionUIModel.shared.logger.log("GroupBox: the template form shows no rows on Linux yet", .warning)
        }
    }

    /// Named after its title, as a group.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// The largest size the GroupBox takes in `orientation` when it expands (LayoutCaps.cap): its
    /// card's, which is its children's plus the padding, and its title's when shown; stacked with
    /// the gap vertically, the larger of them horizontally. A height is for `forSize` wide (-1: no
    /// width given); the vertical box gives the title and the card that width. nil when unbounded.
    static func cap(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int = -1) -> Int? {
        let card = Gtk.Widget(widget).lastChild?.pointer
        var sizes: [Int] = []
        for child in layoutChildren(widget) {
            // An expanding card's cap is its stack's, inside the CSS padding; a measured size
            // includes it.
            let padded = child == card && Gtk.Widget(child).expands(orientation)
            let childForSize = padded && forSize >= 0 ? max(forSize - 2 * contentPadding, 0) : forSize
            guard let size = LayoutCaps.largestSize(child, orientation, forSize: childForSize) else { return nil }
            sizes.append(padded ? size + 2 * contentPadding : size)
        }
        if orientation == GTK_ORIENTATION_VERTICAL {
            return sizes.reduce(0, +) + max(sizes.count - 1, 0) * Int(titleSpacing)
        }
        return sizes.max() ?? 0
    }

    /// A vertical GtkBox whose accessible role is group.
    private static func groupBox() -> WidgetPointer {
        let box = newWidget(gtk_box_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_GROUP)
        gtk_orientable_set_orientation(OpaquePointer(box), GTK_ORIENTATION_VERTICAL)
        gtk_box_set_spacing(typed(box), titleSpacing)
        return box
    }
}
