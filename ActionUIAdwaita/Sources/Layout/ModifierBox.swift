// Sources/Layout/ModifierBox.swift
/*
 The box every element's widget sits in, which applies the base modifiers that change how the
 element is laid out or shown as a whole, in View.applyModifiers' order: padding, then frame
 (both by its layout manager, with FrameSolver's arithmetic), disabled, hidden, opacity and help.
 Parents lay out boxes, not element widgets: a stack sees the frame's size, its expansion
 (the box's expand flags) and its cap (LayoutCaps reads the frame's maximum from the box), and a
 Spacer's marker is carried over to its box.

 - hidden keeps the element's space, as SwiftUI's .hidden() does: the box is transparent and takes
   no input or focus, but it is laid out.
 - A box given more than its frame takes (the window's root, a filling GTK parent) centers the
   frame in the extra space, as SwiftUI's parent would; the content never gets that space.
 - disabled makes the element's widget insensitive, which GTK passes on to its descendants.
*/

import CAdwaita

/// What a box applies, attached to it and set by update.
@MainActor
final class BoxLayout {
    var padding = (horizontal: PaddingAxis(), vertical: PaddingAxis())
    var frame = (horizontal: FrameAxis.none, vertical: FrameAxis.none)
    var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)

    func padding(_ orientation: GtkOrientation) -> PaddingAxis {
        orientation == GTK_ORIENTATION_HORIZONTAL ? padding.horizontal : padding.vertical
    }

    func frame(_ orientation: GtkOrientation) -> FrameAxis {
        orientation == GTK_ORIENTATION_HORIZONTAL ? frame.horizontal : frame.vertical
    }

    func alignment(_ orientation: GtkOrientation) -> StackSolver.Alignment {
        orientation == GTK_ORIENTATION_HORIZONTAL ? alignment.horizontal : alignment.vertical
    }
}

let boxLayoutKey = "actionui-box"

nonisolated(unsafe) private var boxLayoutType: GType = 0

@MainActor
enum ModifierBox {
    /// A new box holding `widget`. The box carries the widget's SpacerMarker, so its stack treats
    /// the box as the Spacer.
    static func wrap(_ widget: WidgetPointer) -> WidgetPointer {
        let box = makeContainer(layoutType: layoutType())
        attach(BoxLayout(), to: box, key: boxLayoutKey)
        if let marker = attached(SpacerMarker.self, on: widget, key: spacerMarkerKey) {
            attach(marker, to: box, key: spacerMarkerKey)
        }
        gtk_widget_set_parent(widget, box)
        return box
    }

    /// Applies the node's base modifiers to its box and its widget.
    static func update(_ box: WidgetPointer, _ node: RenderNode) {
        let modifiers = BaseModifiers(node.properties)
        let widget: WidgetPointer = node.widget
        applyLayout(box, modifiers)

        let sensitive: gboolean = modifiers.disabled == true ? 0 : 1
        if gtk_widget_get_sensitive(widget) != sensitive {
            gtk_widget_set_sensitive(widget, sensitive)
        }
        let opacity = modifiers.hidden ? 0 : min(max(modifiers.opacity ?? 1, 0), 1)
        // GTK keeps opacity in 8 bits (0.5 reads back as 0.502).
        if abs(gtk_widget_get_opacity(box) - opacity) > 1.0 / 255 {
            gtk_widget_set_opacity(box, opacity)
        }
        // Neither the pointer nor keyboard focus reaches a hidden element (can-focus false on the
        // box keeps focus out of its descendants too).
        let targetable: gboolean = modifiers.hidden ? 0 : 1
        if gtk_widget_get_can_target(box) != targetable {
            gtk_widget_set_can_target(box, targetable)
        }
        if gtk_widget_get_can_focus(box) != targetable {
            gtk_widget_set_can_focus(box, targetable)
        }
        let help = modifiers.help.flatMap { $0.isEmpty ? nil : $0 }
        if swiftString(gtk_widget_get_tooltip_text(widget)) != help {
            gtk_widget_set_tooltip_text(widget, help)
        }
    }

    // MARK: Layout settings

    private static func applyLayout(_ box: WidgetPointer, _ modifiers: BaseModifiers) {
        guard let layout = attached(BoxLayout.self, on: box, key: boxLayoutKey) else { return }
        let padding = paddingAxes(modifiers.padding)
        let frame = frameAxes(modifiers.frame)
        let alignment = alignmentAxes(modifiers.frame?.alignment)
        guard layout.padding != padding || layout.frame != frame || layout.alignment != alignment else { return }
        layout.padding = padding
        layout.frame = frame
        layout.alignment = alignment
        setExpand(box, GTK_ORIENTATION_HORIZONTAL, frame.horizontal.expands)
        setExpand(box, GTK_ORIENTATION_VERTICAL, frame.vertical.expands)
        gtk_widget_queue_resize(box)
    }

    /// Forces the box's expansion in one axis, or lets it follow the element (nil).
    private static func setExpand(_ box: WidgetPointer, _ orientation: GtkOrientation, _ expands: Bool?) {
        let horizontal = orientation == GTK_ORIENTATION_HORIZONTAL
        if let expands {
            if horizontal { gtk_widget_set_hexpand(box, expands ? 1 : 0) } else { gtk_widget_set_vexpand(box, expands ? 1 : 0) }
        } else {
            if horizontal { gtk_widget_set_hexpand_set(box, 0) } else { gtk_widget_set_vexpand_set(box, 0) }
        }
    }

    static func paddingAxes(_ padding: BaseModifiers.Padding?) -> (horizontal: PaddingAxis, vertical: PaddingAxis) {
        switch padding {
        case nil:
            return (PaddingAxis(), PaddingAxis())
        case .system:
            let value = FrameSolver.systemPadding
            return (PaddingAxis(before: value, after: value), PaddingAxis(before: value, after: value))
        case let .uniform(length):
            let value = StackSolver.signedLength(length)
            return (PaddingAxis(before: value, after: value), PaddingAxis(before: value, after: value))
        case let .edges(top, leading, bottom, trailing):
            return (PaddingAxis(before: StackSolver.signedLength(leading), after: StackSolver.signedLength(trailing)),
                    PaddingAxis(before: StackSolver.signedLength(top), after: StackSolver.signedLength(bottom)))
        }
    }

    static func frameAxes(_ frame: BaseModifiers.Frame?) -> (horizontal: FrameAxis, vertical: FrameAxis) {
        guard let frame else { return (.none, .none) }
        // As View.applyModifiers does: a fixed frame wins over the flexible keys.
        if frame.isFixed {
            return (FrameAxis(fixed: frame.width.map { StackSolver.length($0) }),
                    FrameAxis(fixed: frame.height.map { StackSolver.length($0) }))
        }
        return (.flexible(minimum: frame.minWidth.map(length), ideal: frame.idealWidth.map(length), maximum: frame.maxWidth.map(maximum)),
                .flexible(minimum: frame.minHeight.map(length), ideal: frame.idealHeight.map(length), maximum: frame.maxHeight.map(maximum)))
    }

    private static func length(_ value: Double) -> Int {
        StackSolver.length(value)
    }

    private static func maximum(_ value: Double) -> Int {
        value == .infinity ? FrameAxis.infinity : StackSolver.length(value)
    }

    static func alignmentAxes(_ alignment: BaseModifiers.AlignmentName?) -> (horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment) {
        switch alignment ?? .center {
        case .center: return (.center, .center)
        case .leading: return (.start, .center)
        case .trailing: return (.end, .center)
        case .top: return (.center, .start)
        case .bottom: return (.center, .end)
        case .topLeading: return (.start, .start)
        case .topTrailing: return (.end, .start)
        case .bottomLeading: return (.start, .end)
        case .bottomTrailing: return (.end, .end)
        }
    }

    // MARK: The layout manager

    static func layoutType() -> GType {
        if boxLayoutType != 0 { return boxLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { ModifierBox.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { ModifierBox.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        boxLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIModifierLayout", &info, GTypeFlags(0))
        return boxLayoutType
    }

    private static func layout(_ box: WidgetPointer) -> BoxLayout {
        attached(BoxLayout.self, on: box, key: boxLayoutKey) ?? BoxLayout()
    }

    private static func other(_ orientation: GtkOrientation) -> GtkOrientation {
        orientation == GTK_ORIENTATION_HORIZONTAL ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
    }

    private static func measureChild(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(child, orientation, Int32(clamping: forSize), &minimum, &natural, nil, nil)
        return (Int(minimum), Int(natural))
    }

    /// The frame's and the child's sizes in one axis when the box is `boxSize` in that axis: the
    /// frame takes what it does of the box (a parent may give more than the frame asked for), the
    /// child is offered the frame less the padding and takes that clamped to its range.
    private static func childSize(_ child: WidgetPointer, _ layout: BoxLayout, _ orientation: GtkOrientation,
                                  boxSize: Int, forSize: Int = -1) -> (frame: Int, content: Int) {
        let measured = measureChild(child, orientation, forSize: forSize)
        let padding = layout.padding(orientation)
        let expands = gtk_widget_compute_expand(child, orientation) != 0
        let frame = layout.frame(orientation).size(in: boxSize, contentMinimum: measured.minimum + padding.total,
                                                   contentNatural: measured.natural + padding.total, contentExpands: expands)
        let content = FrameSolver.contentSize(in: frame, padding: padding, minimum: measured.minimum,
                                              natural: measured.natural, expands: expands)
        return (frame, content)
    }

    private static func measure(_ box: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let child = layoutChildren(box).first else { return (0, 0) }
        let layout = layout(box)
        // Height for width: the child's height for the width it gets in a box that wide.
        var childForSize = -1
        if forSize >= 0, orientation == GTK_ORIENTATION_VERTICAL {
            childForSize = childSize(child, layout, GTK_ORIENTATION_HORIZONTAL, boxSize: forSize).content
        }
        let measured = measureChild(child, orientation, forSize: childForSize)
        let padding = layout.padding(orientation).total
        let frame = layout.frame(orientation)
        let contentMinimum = measured.minimum + padding
        let contentNatural = measured.natural + padding
        // Negative padding can take the padded size below 0; GTK sizes are never negative.
        return (max(frame.minimumSize(content: contentMinimum), 0),
                max(frame.naturalSize(content: contentNatural, contentMinimum: contentMinimum), 0))
    }

    private static func allocate(_ box: WidgetPointer, width: Int, height: Int) {
        guard let child = layoutChildren(box).first else { return }
        let layout = layout(box)
        let widths = childSize(child, layout, GTK_ORIENTATION_HORIZONTAL, boxSize: width)
        let heights = childSize(child, layout, GTK_ORIENTATION_VERTICAL, boxSize: height, forSize: widths.content)
        // The frame is centered in a box bigger than it (as SwiftUI's parent centers it); the
        // content is aligned in the frame less the padding.
        let horizontal = layout.padding.horizontal
        let vertical = layout.padding.vertical
        let x = StackSolver.centeredStart(length: widths.frame, available: width) + horizontal.before
            + StackSolver.alignedOffset(size: widths.content, block: widths.frame - horizontal.total,
                                        alignment: layout.alignment.horizontal)
        let y = StackSolver.centeredStart(length: heights.frame, available: height) + vertical.before
            + StackSolver.alignedOffset(size: heights.content, block: heights.frame - vertical.total,
                                        alignment: layout.alignment.vertical)
        var origin = graphene_point_t(x: Float(x), y: Float(y))
        gtk_widget_allocate(child, Int32(clamping: widths.content), Int32(clamping: heights.content), -1,
                            gsk_transform_translate(nil, &origin))
    }
}
