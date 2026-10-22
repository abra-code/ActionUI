// Sources/Elements/GroupBox+Adwaita.swift
/*
 GroupBox on GTK: its children in a libadwaita card, under its title when it has one, as macOS
 puts a GroupBox's title above its box. Measured on macOS 27 (the layout parity fixtures): the
 content is inset 5 points on every side, the children are centered and 8 points apart (where a
 VStack of the same views puts none), and the box is as large as its children unless one of them
 fills. A title puts the box 17 points lower; here the title label and a 4 px gap do.

 The element widget is a group for assistive technologies, named after the title.

 Not yet: the template form (rows from setElementRows) shows no rows; logged once.
*/

import CAdwaita

@MainActor private var reportedTemplate = false

/// Attached to a GroupBox's widget: LayoutCaps finds how far the GroupBox expands through it.
@MainActor
final class GroupBoxMarker {}

let groupBoxMarkerKey = "actionui-groupbox"

extension GroupBox: ActionUIAdwaitaRenderer {
    /// The content's inset on every side, measured on macOS 27.
    static let contentPadding = 5
    /// The spacing between children, measured on macOS 27.
    static let childSpacing = 8.0
    /// The gap between the title and the box.
    static let titleSpacing: Int32 = 4

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let group = groupBox()
        let title = gtk_label_new(nil)!
        gtk_label_set_xalign(opaque(title), 0)
        gtk_widget_set_visible(title, 0)
        gtk_box_append(typed(group), title)
        let content = StackLayout.makeStack(axis: .vertical)
        gtk_widget_add_css_class(content, "card")
        StyleSheet.shared.apply(["padding: \(contentPadding)px;"], to: content, slot: "groupBoxPadding")
        StackLayout.configure(content, spacing: childSpacing, alignment: .center)
        gtk_box_append(typed(group), content)
        attach(GroupBoxMarker(), to: group, key: groupBoxMarkerKey)
        return group
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let title = gtk_widget_get_first_child(widget), let content = gtk_widget_get_last_child(widget) else { return }
        let text = Props(node.properties).title ?? ""
        if swiftString(gtk_label_get_text(opaque(title))) != text {
            gtk_label_set_text(opaque(title), text)
        }
        let showsTitle: gboolean = text.isEmpty ? 0 : 1
        if gtk_widget_get_visible(title) != showsTitle {
            gtk_widget_set_visible(title, showsTitle)
        }
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
    /// the gap vertically, the larger of them horizontally. nil when unbounded.
    static func cap(_ widget: WidgetPointer, _ orientation: GtkOrientation) -> Int? {
        let card = gtk_widget_get_last_child(widget)
        var sizes: [Int] = []
        for child in layoutChildren(widget) {
            guard let size = LayoutCaps.largestSize(child, orientation) else { return nil }
            // An expanding card's cap is its stack's, inside the CSS padding; a measured size
            // includes it.
            let padded = child == card && gtk_widget_compute_expand(child, orientation) != 0
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
