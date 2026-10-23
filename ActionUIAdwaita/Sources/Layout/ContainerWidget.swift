// Sources/Layout/ContainerWidget.swift
/*
 The widget every ActionUI layout container uses: a GtkWidget subclass, registered from Swift,
 that takes its layout manager per instance (StackLayout, and the other layouts) and unparents its
 children when it is disposed. GtkBox is not used because its API assumes its own layout manager.
 Also the reconciliation of a container's children with its element's.
*/

import CAdwaita

nonisolated(unsafe) private var containerType: GType = 0
nonisolated(unsafe) private var containerParentClass: UnsafeMutablePointer<GObjectClass>?
nonisolated(unsafe) private var containerParentWidgetClass: UnsafeMutablePointer<GtkWidgetClass>?

@MainActor func actionUIContainerType() -> GType {
    if containerType != 0 { return containerType }
    var info = GTypeInfo()
    info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
    info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
    info.class_init = { klass, _ in
        guard let klass else { return }
        containerParentClass = g_type_class_peek_parent(klass)?.assumingMemoryBound(to: GObjectClass.self)
        containerParentWidgetClass = g_type_class_peek_parent(klass)?.assumingMemoryBound(to: GtkWidgetClass.self)
        let objectClass = klass.assumingMemoryBound(to: GObjectClass.self)
        objectClass.pointee.dispose = { object in
            guard let object else { return }
            let widget: WidgetPointer = typed(object)
            while let child = gtk_widget_get_first_child(widget) {
                gtk_widget_unparent(child)
            }
            containerParentClass?.pointee.dispose?(object)
        }
        let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
        // A container expands where a child does, as a SwiftUI stack becomes flexible through its
        // children (GtkWidget's own default says no; GtkBox does the same as this). Hidden
        // children do not expand.
        widgetClass.pointee.compute_expand = { widget, hexpand, vexpand in
            var horizontal = false
            var vertical = false
            var child = widget.flatMap { gtk_widget_get_first_child($0) }
            while let current = child {
                horizontal = horizontal || gtk_widget_compute_expand(current, GTK_ORIENTATION_HORIZONTAL) != 0
                vertical = vertical || gtk_widget_compute_expand(current, GTK_ORIENTATION_VERTICAL) != 0
                child = gtk_widget_get_next_sibling(current)
            }
            hexpand?.pointee = horizontal ? 1 : 0
            vexpand?.pointee = vertical ? 1 : 0
        }
        // The widgets of a Group that spans its stack (its box and content group derive from this
        // type too) contain no point of their own, so picking passes through them
        // (Group.passesPicks).
        widgetClass.pointee.contains = { widget, x, y in
            guard let widget else { return 0 }
            if MainActor.assumeIsolated({ Group.passesPicks(widget) }) { return 0 }
            return containerParentWidgetClass?.pointee.contains?(widget, x, y) ?? 0
        }
        gtk_widget_class_set_css_name(widgetClass, "actionui-container")
        gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_GROUP)
    }
    containerType = g_type_register_static(gtk_widget_get_type(), "ActionUIContainer", &info, GTypeFlags(0))
    return containerType
}

/// A new container widget laid out by a new instance of `layoutType` (a GtkLayoutManager
/// subclass). The widget comes with GTK's floating reference, as gtk_*_new returns.
@MainActor func makeContainer(layoutType: GType) -> WidgetPointer {
    let widget: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(actionUIContainerType(), 0, nil, nil)!))
    let manager: UnsafeMutablePointer<GtkLayoutManager> = typed(OpaquePointer(g_object_new_with_properties(layoutType, 0, nil, nil)!))
    // The widget takes the manager's only reference.
    gtk_widget_set_layout_manager(widget, manager)
    return widget
}

/// Makes `container`'s children the boxes of `elements`' nodes, in order: new ones are added,
/// moved ones moved, removed ones taken out.
@MainActor func syncContainerChildren(_ node: RenderNode, _ container: WidgetPointer,
                                      _ elements: [any ActionUIElementBase]) {
    var previous: WidgetPointer?
    node.syncChildren(elements, insert: { child, _ in
        let widget: WidgetPointer = child.outerWidget
        // Already in place: nothing to do (gtk_widget_insert_after would still relayout).
        if gtk_widget_get_parent(widget) != container || gtk_widget_get_prev_sibling(widget) != previous {
            gtk_widget_insert_after(widget, container, previous)
        }
        previous = widget
    }, remove: { child in
        gtk_widget_unparent(child.outerWidget)
    })
}

/// The visible children of a container widget, in order: the ones its layout places.
@MainActor func layoutChildren(_ widget: WidgetPointer) -> [WidgetPointer] {
    var children: [WidgetPointer] = []
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if gtk_widget_should_layout(current) != 0 {
            children.append(current)
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return children
}
