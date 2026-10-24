// Sources/Layout/ListRowLayout.swift
/*
 The holder of a List row's child on GTK: a container that places its one child at the row's
 leading edge, as SwiftUI places a row's content (a frame as wide as the row, aligned leading): the
 child takes what a stack child takes of the row's width (its natural width, or all of it up to
 its frame's maximum when it expands) and is centered vertically.
*/

import CAdwaita

nonisolated(unsafe) private var listRowLayoutType: GType = 0

@MainActor
enum ListRowLayout {
    /// A new, empty row holder.
    static func makeHolder() -> WidgetPointer {
        makeContainer(layoutType: layoutType())
    }

    static func layoutType() -> GType {
        if listRowLayoutType != 0 { return listRowLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { ListRowLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { ListRowLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        listRowLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIListRowLayout", &info, GTypeFlags(0))
        return listRowLayoutType
    }

    /// The child's width in a row `width` wide.
    private static func childWidth(_ child: WidgetPointer, width: Int) -> Int {
        let size = Gtk.Widget(child).measure(GTK_ORIENTATION_HORIZONTAL)
        let range: StackChild = Gtk.Widget(child).expands(GTK_ORIENTATION_HORIZONTAL)
            ? .expanding(minimum: size.minimum, cap: LayoutCaps.cap(child, GTK_ORIENTATION_HORIZONTAL))
            : .fixed(minimum: size.minimum, natural: size.natural)
        return range.size(offered: width)
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let child = layoutChildren(widget).first else { return (0, 0) }
        // Height for width: the child's height at the width allocate gives it.
        let childForSize = orientation == GTK_ORIENTATION_VERTICAL && forSize >= 0 ? childWidth(child, width: forSize) : -1
        let size = Gtk.Widget(child).measure(orientation, forSize: childForSize)
        return (size.minimum, size.natural)
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        guard let child = layoutChildren(widget).first else { return }
        let childWidth = childWidth(child, width: width)
        let size = Gtk.Widget(child).measure(GTK_ORIENTATION_VERTICAL, forSize: childWidth)
        let childHeight = Gtk.Widget(child).expands(GTK_ORIENTATION_VERTICAL) ? max(height, size.minimum) : min(max(size.natural, size.minimum), max(height, size.minimum))
        var origin = graphene_point_t(x: 0, y: Float(StackSolver.centeredStart(length: childHeight, available: height)))
        gtk_widget_allocate(child, Int32(clamping: childWidth), Int32(clamping: childHeight), -1,
                            gsk_transform_translate(nil, &origin))
    }
}
