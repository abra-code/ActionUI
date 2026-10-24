// Sources/Elements/ScrollView+Adwaita.swift
/*
 ScrollView on GTK: a GtkScrolledWindow holding a ScrollLayout container, which sizes and places
 the content as SwiftUI does. Measured on macOS 27 (the scrollview layout parity fixtures): a
 ScrollView expands along its scroll axes (two of them in a stack share the space like two
 Colors) and takes its content's size across them (a vertical one beside a Color is as wide as its
 content, all of the space when the content expands).

 The scrollbars: scrolling is off across the scroll axes; showsIndicators false keeps scrolling
 without a scrollbar (GTK_POLICY_EXTERNAL). macOS draws overlay scrollers, as libadwaita does, so
 the scrollbars take no space on either.

 Not here: onRefreshActionID (pull to refresh, which desktops do not have). Scrolling to an element
 is ScrollViewReader's (ScrollViewReader+Adwaita.swift).
*/

import CAdwaita

extension ScrollView: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let scroller = gtk_scrolled_window_new()!
        let content = ScrollLayout.makeContent()
        // The scrolled window wraps the container in a GtkViewport, which scrolls it.
        gtk_scrolled_window_set_child(OpaquePointer(scroller), content)
        let configuration = ScrollConfiguration(content: content)
        attach(configuration, to: scroller, key: scrollConfigurationKey)
        attach(configuration, to: content, key: scrollConfigurationKey)
        return scroller
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let configuration = attached(on: widget, key: scrollConfigurationKey) else { return }
        let props = Props(node.properties)
        if configuration.axis != props.axis {
            configuration.axis = props.axis
            gtk_widget_queue_resize(configuration.content)
        }
        let scroller = OpaquePointer(widget)
        let scrolling = props.showsIndicators ? GTK_POLICY_AUTOMATIC : GTK_POLICY_EXTERNAL
        let horizontal = configuration.scrolls(GTK_ORIENTATION_HORIZONTAL)
        let vertical = configuration.scrolls(GTK_ORIENTATION_VERTICAL)
        let policies = (horizontal ? scrolling : GTK_POLICY_NEVER, vertical ? scrolling : GTK_POLICY_NEVER)
        var current = (GTK_POLICY_NEVER, GTK_POLICY_NEVER)
        gtk_scrolled_window_get_policy(scroller, &current.0, &current.1)
        if current != policies {
            gtk_scrolled_window_set_policy(scroller, policies.0, policies.1)
        }
        // Across a scroll axis the scrolled window asks for its content's natural size.
        let propagatesWidth: gboolean = horizontal ? 0 : 1
        if gtk_scrolled_window_get_propagate_natural_width(scroller) != propagatesWidth {
            gtk_scrolled_window_set_propagate_natural_width(scroller, propagatesWidth)
        }
        let propagatesHeight: gboolean = vertical ? 0 : 1
        if gtk_scrolled_window_get_propagate_natural_height(scroller) != propagatesHeight {
            gtk_scrolled_window_set_propagate_natural_height(scroller, propagatesHeight)
        }
        // Expanding along a scroll axis; across, it expands where its content does (the scrolled
        // window computes that from its child).
        setExpand(widget, GTK_ORIENTATION_HORIZONTAL, horizontal)
        setExpand(widget, GTK_ORIENTATION_VERTICAL, vertical)

        let content = node.effectiveElement.subviews?["content"] as? any ActionUIElementBase
        syncContainerChildren(node, configuration.content, content.map { [$0] } ?? [])
    }

    /// Forces expansion in `orientation` when the ScrollView scrolls there, or lets GTK compute it
    /// from the content.
    private static func setExpand(_ widget: WidgetPointer, _ orientation: GtkOrientation, _ scrolls: Bool) {
        let horizontal = orientation == GTK_ORIENTATION_HORIZONTAL
        let isSet = (horizontal ? gtk_widget_get_hexpand_set(widget) : gtk_widget_get_vexpand_set(widget)) != 0
        if scrolls {
            if !isSet || !Gtk.Widget(widget).expands(orientation) {
                if horizontal { gtk_widget_set_hexpand(widget, 1) } else { gtk_widget_set_vexpand(widget, 1) }
            }
        } else if isSet {
            if horizontal { gtk_widget_set_hexpand_set(widget, 0) } else { gtk_widget_set_vexpand_set(widget, 0) }
        }
    }
}
