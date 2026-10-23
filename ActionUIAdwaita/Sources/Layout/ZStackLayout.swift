// Sources/Layout/ZStackLayout.swift
/*
 ZStack on GTK: a GtkLayoutManager subclass that layers a container's children, as SwiftUI's
 ZStack does: every child is offered the stack's whole size and takes it clamped to its range (a
 child that expands takes all of it, up to its frame's maximum); the stack is as big as its
 biggest child in each axis, centered in the space it is given; each child is aligned inside it
 by the stack's alignment. Children are drawn in order, the last on top.
*/

import CAdwaita

/// A ZStack's alignment, attached to its container widget; the renderer's update sets it.
@MainActor
final class ZStackConfiguration {
    var horizontal: StackSolver.Alignment = .center
    var vertical: StackSolver.Alignment = .center
}

let zStackConfigurationKey = "actionui-zstack"

nonisolated(unsafe) private var zStackLayoutType: GType = 0

@MainActor
enum ZStackLayout {
    /// A new, empty ZStack container.
    static func makeStack() -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        attach(ZStackConfiguration(), to: widget, key: zStackConfigurationKey)
        return widget
    }

    /// Sets the alignment, relaying the stack out only when it changed.
    static func configure(_ widget: WidgetPointer, horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment) {
        guard let configuration = attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey),
              configuration.horizontal != horizontal || configuration.vertical != vertical else { return }
        configuration.horizontal = horizontal
        configuration.vertical = vertical
        gtk_widget_queue_resize(widget)
    }

    static func layoutType() -> GType {
        if zStackLayoutType != 0 { return zStackLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { ZStackLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { ZStackLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        zStackLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIZStackLayout", &info, GTypeFlags(0))
        return zStackLayoutType
    }

    /// A child's size in one axis when offered `available`, measured for `forSize` in the other.
    private static func childSize(_ child: WidgetPointer, _ orientation: GtkOrientation, available: Int, forSize: Int = -1) -> Int {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(child, orientation, Int32(clamping: forSize), &minimum, &natural, nil, nil)
        let range: StackChild
        if gtk_widget_compute_expand(child, orientation) != 0 {
            range = .expanding(minimum: Int(minimum), cap: LayoutCaps.cap(child, orientation, forSize: forSize))
        } else {
            range = .fixed(minimum: Int(minimum), natural: Int(natural))
        }
        return range.size(offered: available)
    }

    /// Each child's width when the stack is `width` wide, as allocate gives them.
    static func childWidths(_ widget: WidgetPointer, width: Int) -> [Int] {
        layoutChildren(widget).map { childSize($0, GTK_ORIENTATION_HORIZONTAL, available: width) }
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        var result = (minimum: 0, natural: 0)
        for child in layoutChildren(widget) {
            // Height for width: each child's height for the width it gets in a stack that wide.
            var childForSize = -1
            if forSize >= 0, orientation == GTK_ORIENTATION_VERTICAL {
                childForSize = childSize(child, GTK_ORIENTATION_HORIZONTAL, available: forSize)
            }
            var minimum: Int32 = 0
            var natural: Int32 = 0
            gtk_widget_measure(child, orientation, Int32(clamping: childForSize), &minimum, &natural, nil, nil)
            result.minimum = max(result.minimum, Int(minimum))
            result.natural = max(result.natural, Int(natural))
        }
        return result
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        let children = layoutChildren(widget)
        guard !children.isEmpty else { return }
        let configuration = attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) ?? ZStackConfiguration()
        let widths = children.map { childSize($0, GTK_ORIENTATION_HORIZONTAL, available: width) }
        let heights = children.enumerated().map { childSize($1, GTK_ORIENTATION_VERTICAL, available: height, forSize: widths[$0]) }
        let blockWidth = widths.max() ?? 0
        let blockHeight = heights.max() ?? 0
        let blockX = StackSolver.centeredStart(length: blockWidth, available: width)
        let blockY = StackSolver.centeredStart(length: blockHeight, available: height)
        for (index, child) in children.enumerated() {
            let x = blockX + StackSolver.alignedOffset(size: widths[index], block: blockWidth, alignment: configuration.horizontal)
            let y = blockY + StackSolver.alignedOffset(size: heights[index], block: blockHeight, alignment: configuration.vertical)
            var origin = graphene_point_t(x: Float(x), y: Float(y))
            gtk_widget_allocate(child, Int32(clamping: widths[index]), Int32(clamping: heights[index]), -1,
                                gsk_transform_translate(nil, &origin))
        }
    }
}
