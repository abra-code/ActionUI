// Sources/Layout/ScrollLayout.swift
/*
 The content of a ScrollView on GTK: a container inside the GtkScrolledWindow's viewport that
 sizes and places the ScrollView's content as SwiftUI does (measured on macOS 27, the scrollview
 layout parity fixtures):

 - along a scroll axis the content has its natural size (SwiftUI's ideal size: an unframed Color
   is 10 long, not stretched to the ScrollView), at the start (top, leading);
 - across a vertical or horizontal ScrollView the content is offered the ScrollView's size and
   takes what a stack child would (a fixed size up to its natural one, an expanding one all of it
   up to its frame's maximum), centered.

 Along a scroll axis the container's minimum is its natural size, so the viewport scrolls over the
 whole content whatever its scroll policy. The ScrollView itself (GtkScrolledWindow) expands along
 its scroll axes and takes the content's size across, as SwiftUI's does.
*/

import CAdwaita

/// A ScrollView's axes and its content container, attached to its GtkScrolledWindow and to the
/// content container.
@MainActor
final class ScrollConfiguration {
    var axis: ScrollView.Props.Axis = .vertical
    /// The container inside the viewport (held by the widget tree).
    let content: WidgetPointer

    init(content: WidgetPointer) {
        self.content = content
    }

    /// Whether the content scrolls in `orientation`.
    func scrolls(_ orientation: GtkOrientation) -> Bool {
        switch axis {
        case .vertical: return orientation == GTK_ORIENTATION_VERTICAL
        case .horizontal: return orientation == GTK_ORIENTATION_HORIZONTAL
        case .both: return true
        }
    }
}

let scrollConfigurationKey = AttachKey<ScrollConfiguration>("actionui-scroll")

nonisolated(unsafe) private var scrollLayoutType: GType = 0

@MainActor
enum ScrollLayout {
    /// A new, empty content container.
    static func makeContent() -> WidgetPointer {
        makeContainer(layoutType: layoutType())
    }

    static func layoutType() -> GType {
        if scrollLayoutType != 0 { return scrollLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { ScrollLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { ScrollLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        scrollLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIScrollLayout", &info, GTypeFlags(0))
        return scrollLayoutType
    }

    private static func configuration(_ widget: WidgetPointer) -> ScrollConfiguration? {
        attached(on: widget, key: scrollConfigurationKey)
    }

    /// The content's size across the scroll axis when the container is `available` long there: what
    /// a stack child takes when offered that, measured for `forSize` in the other axis (-1: none).
    private static func crossSize(_ child: WidgetPointer, _ orientation: GtkOrientation, available: Int, forSize: Int = -1) -> Int {
        let size = Gtk.Widget(child).measure(orientation, forSize: forSize)
        let range: StackChild
        if Gtk.Widget(child).expands(orientation) {
            range = .expanding(minimum: size.minimum, cap: LayoutCaps.cap(child, orientation, forSize: forSize))
        } else {
            range = .fixed(minimum: size.minimum, natural: size.natural)
        }
        return range.size(offered: available)
    }

    /// The content's natural size along a scroll axis, for `forSize` in the other (-1: none).
    private static func scrollSize(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> Int {
        let size = Gtk.Widget(child).measure(orientation, forSize: forSize)
        return max(size.natural, size.minimum)
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let child = layoutChildren(widget).first else { return (0, 0) }
        // Height for width: the content's height at the width allocate gives it (its natural width
        // when it scrolls horizontally, whatever the container's width).
        let childForSize = orientation == GTK_ORIENTATION_VERTICAL ? childWidth(widget, child, width: forSize) : -1
        let scrolls = configuration(widget)?.scrolls(orientation) ?? true
        if !scrolls {
            let size = Gtk.Widget(child).measure(orientation, forSize: childForSize)
            return (size.minimum, size.natural)
        }
        let length = scrollSize(child, orientation, forSize: childForSize)
        return (length, length)
    }

    /// The content's width in a container `width` wide (-1 when no width is given, unless the
    /// content scrolls horizontally: then its natural width, which needs none).
    private static func childWidth(_ widget: WidgetPointer, _ child: WidgetPointer, width: Int) -> Int {
        if configuration(widget)?.scrolls(GTK_ORIENTATION_HORIZONTAL) ?? true {
            return scrollSize(child, GTK_ORIENTATION_HORIZONTAL, forSize: -1)
        }
        guard width >= 0 else { return -1 }
        return crossSize(child, GTK_ORIENTATION_HORIZONTAL, available: width)
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        guard let child = layoutChildren(widget).first else { return }
        let scrollsVertically = configuration(widget)?.scrolls(GTK_ORIENTATION_VERTICAL) ?? true
        let childWidth = childWidth(widget, child, width: width)
        let childHeight: Int
        if scrollsVertically {
            childHeight = scrollSize(child, GTK_ORIENTATION_VERTICAL, forSize: childWidth)
        } else {
            childHeight = crossSize(child, GTK_ORIENTATION_VERTICAL, available: height, forSize: childWidth)
        }
        // Centered across the scroll axis, at the start along it.
        let scrollsHorizontally = configuration(widget)?.scrolls(GTK_ORIENTATION_HORIZONTAL) ?? true
        let x = scrollsHorizontally ? 0 : StackSolver.centeredStart(length: childWidth, available: width)
        let y = scrollsVertically ? 0 : StackSolver.centeredStart(length: childHeight, available: height)
        var origin = graphene_point_t(x: Float(x), y: Float(y))
        gtk_widget_allocate(child, Int32(clamping: childWidth), Int32(clamping: childHeight), -1,
                            gsk_transform_translate(nil, &origin))
        // A ScrollViewReader around it may be waiting for this layout to scroll.
        ScrollViewReader.layoutChanged(widget)
    }

    /// The largest size a ScrollView takes in `orientation` when it expands (LayoutCaps.cap):
    /// unbounded along a scroll axis, its content's largest size across.
    static func cap(_ configuration: ScrollConfiguration, _ orientation: GtkOrientation, forSize: Int) -> Int? {
        guard !configuration.scrolls(orientation), let child = layoutChildren(configuration.content).first else { return nil }
        // A height for the width the content gets in a ScrollView `forSize` wide.
        let childForSize = orientation == GTK_ORIENTATION_VERTICAL ? childWidth(configuration.content, child, width: forSize) : -1
        return LayoutCaps.largestSize(child, orientation, forSize: childForSize)
    }
}
