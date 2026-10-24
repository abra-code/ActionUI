// Sources/Elements/GeometryReader+Adwaita.swift
/*
 GeometryReader on GTK, as on Apple (measured: the geometry-* layout parity fixtures): greedy, it
 expands in both axes and shares a stack like a Color, its minimum 0 and its natural size SwiftUI's
 ideal 10 x 10 whatever its content (a Color's); it offers its content its whole size, which the
 content takes clamped to its range (all of it where it expands), and places the content at its
 alignment (top leading unless set; content larger than the reader starts at its top leading corner
 in that axis). Its size goes to states["size"] as [width, height] after
 each layout that changes it, as SwiftUI reports it on appear and on change.
*/

import CAdwaita

nonisolated(unsafe) private var geometryLayoutType: GType = 0
private let geometryStateKey = AttachKey<GeometryState>("actionui-geometry")

/// A GeometryReader's alignment and the size it last reported, attached to its container.
@MainActor private final class GeometryState {
    var horizontal = StackSolver.Alignment.start
    var vertical = StackSolver.Alignment.start
    weak var node: RenderNode?
    var reported: [Double]?
}

extension GeometryReader: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        let state = GeometryState()
        state.node = node
        attach(state, to: widget, key: geometryStateKey)
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: geometryStateKey) else { return }
        let content = node.effectiveElement.subviews?["content"] as? any ActionUIElementBase
        syncContainerChildren(node, widget, content.map { [$0] } ?? [])
        let (horizontal, vertical) = alignment(Props(node.properties).alignment)
        if horizontal != state.horizontal || vertical != state.vertical {
            state.horizontal = horizontal
            state.vertical = vertical
            gtk_widget_queue_allocate(widget)
        }
    }

    private static func alignment(_ alignment: Props.Alignment) -> (StackSolver.Alignment, StackSolver.Alignment) {
        switch alignment {
        case .topLeading: return (.start, .start)
        case .top: return (.center, .start)
        case .topTrailing: return (.end, .start)
        case .leading: return (.start, .center)
        case .center: return (.center, .center)
        case .trailing: return (.end, .center)
        case .bottomLeading: return (.start, .end)
        case .bottom: return (.center, .end)
        case .bottomTrailing: return (.end, .end)
        }
    }

    // MARK: Layout

    static func layoutType() -> GType {
        if geometryLayoutType != 0 { return geometryLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            // Any size from 0, SwiftUI's ideal 10 x 10 naturally whatever the content (measured:
            // geometry-in-scrollview), as a Color is.
            layoutClass.pointee.measure = { _, _, _, _, minimum, natural, minimumBaseline, naturalBaseline in
                minimum?.pointee = 0
                natural?.pointee = MainActor.assumeIsolated { Color.idealLength }
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { GeometryReader.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        geometryLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIGeometryLayout", &info, GTypeFlags(0))
        return geometryLayoutType
    }

    /// The content's size in `orientation` when offered `available`.
    private static func contentSize(_ content: WidgetPointer, _ orientation: GtkOrientation, available: Int, forSize: Int = -1) -> Int {
        let size = Gtk.Widget(content).measure(orientation, forSize: forSize)
        let range: StackChild = Gtk.Widget(content).expands(orientation)
            ? .expanding(minimum: size.minimum, cap: LayoutCaps.cap(content, orientation, forSize: forSize))
            : .fixed(minimum: size.minimum, natural: size.natural)
        return range.size(offered: available)
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        guard let state = attached(on: widget, key: geometryStateKey) else { return }
        report(state, width: width, height: height)
        guard let content = layoutChildren(widget).first else { return }
        let contentWidth = contentSize(content, GTK_ORIENTATION_HORIZONTAL, available: width)
        let contentHeight = contentSize(content, GTK_ORIENTATION_VERTICAL, available: height, forSize: contentWidth)
        // Content larger than the reader starts at its top leading corner whatever the alignment
        // (measured: geometry-overflow-center), as SwiftUI aligns it in a frame at least its size.
        var origin = graphene_point_t(x: Float(max(0, StackSolver.alignedOffset(size: contentWidth, block: width, alignment: state.horizontal))),
                                      y: Float(max(0, StackSolver.alignedOffset(size: contentHeight, block: height, alignment: state.vertical))))
        gtk_widget_allocate(content, Int32(clamping: contentWidth), Int32(clamping: contentHeight), -1, gsk_transform_translate(nil, &origin))
    }

    /// Writes the size to states["size"] after this layout, when it changed: a write during the
    /// layout would sync the window while GTK lays it out.
    private static func report(_ state: GeometryState, width: Int, height: Int) {
        let size = [Double(width), Double(height)]
        guard size != state.reported else { return }
        state.reported = size
        _ = runAfter(milliseconds: 0) { [weak state] in
            guard let state, let node = state.node, state.reported == size,
                  node.model.states["size"] as? [Double] != size else { return }
            node.model.states["size"] = size
        }
    }
}
