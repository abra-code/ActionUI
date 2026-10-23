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
        stackChildren(widget).map { childSize($0, GTK_ORIENTATION_HORIZONTAL, available: width) }
    }

    /// Where each child starts across a stack `width` wide, and its width, as allocate places it:
    /// in a block as wide as the widest child, centered, each aligned in the block by the stack's
    /// horizontal alignment. FormLayout reads it to find the titles inside a row.
    static func horizontalPlacements(_ widget: WidgetPointer, width: Int) -> [(x: Int, width: Int)] {
        let configuration = attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) ?? ZStackConfiguration()
        let widths = childWidths(widget, width: width)
        let block = widths.max() ?? 0
        let blockX = StackSolver.centeredStart(length: block, available: width)
        return widths.map { (blockX + StackSolver.alignedOffset(size: $0, block: block, alignment: configuration.horizontal), $0) }
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        var result = (minimum: 0, natural: 0)
        for child in stackChildren(widget) {
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
        Group.allocateGroups(in: widget, width: width, height: height)
        let children = stackChildren(widget)
        guard !children.isEmpty else { return }
        for (child, place) in zip(children, placements(widget, width: width, height: height)) {
            var origin = graphene_point_t(x: Float(place.x), y: Float(place.y))
            gtk_widget_allocate(child, Int32(clamping: place.width), Int32(clamping: place.height), -1,
                                gsk_transform_translate(nil, &origin))
        }
    }

    /// Each child's place and size in a stack `width` x `height`, as allocate gives them: across
    /// as horizontalPlacements, and down in a block as tall as the tallest child, centered, each
    /// aligned in it by the stack's vertical alignment (Baselines reads them too).
    static func placements(_ widget: WidgetPointer, width: Int, height: Int) -> [(x: Int, y: Int, width: Int, height: Int)] {
        let configuration = attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) ?? ZStackConfiguration()
        let across = horizontalPlacements(widget, width: width)
        let heights = zip(stackChildren(widget), across).map {
            childSize($0, GTK_ORIENTATION_VERTICAL, available: height, forSize: $1.width)
        }
        let blockHeight = heights.max() ?? 0
        let blockY = StackSolver.centeredStart(length: blockHeight, available: height)
        return heights.indices.map { index in
            let y = blockY + StackSolver.alignedOffset(size: heights[index], block: blockHeight, alignment: configuration.vertical)
            return (across[index].x, y, across[index].width, heights[index])
        }
    }
}
