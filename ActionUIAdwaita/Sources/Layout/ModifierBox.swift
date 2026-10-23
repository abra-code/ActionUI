// Sources/Layout/ModifierBox.swift
/*
 The box every element's widget sits in, which applies the base modifiers, in
 View.applyModifiers' order. Two widgets, so painting follows the frame, not the space the box is
 given:

   ModifierBox (outer)    the frame (fixed, min, ideal, max) by its layout manager, with
                          FrameSolver's arithmetic; offset, rotation and scale in the transform it
                          gives the content group; hidden, opacity; the shadow, drawn in the shape
                          of what is drawn as SwiftUI's is (not a box shadow)
     content group        exactly the frame's size: the padding and the element's alignment in
                          it; background, cornerRadius and clipShape (rounded and clipped), border
       element widget     disabled, help; font, foregroundStyle and tint, which its descendants
                          inherit; the accessibility label, hint, hidden state and identifier
                          (the box and the content group have the generic role, unnamed
                          panels assistive technologies pass over: GTK leaves a presentation
                          or none widget out of the tree with all its descendants)

 Parents lay out the outer box: a stack sees the frame's size, its expansion (the box's expand
 flags) and its cap (LayoutCaps reads the frame from the box), and a Spacer's marker is carried
 over to its box.

 - hidden keeps the element's space, as SwiftUI's .hidden() does: the box is transparent and takes
   no input or focus, but it is laid out.
 - A box given more than its frame takes (the window's root, a filling GTK parent) centers the
   frame in the extra space, as SwiftUI's parent would; the content never gets that space, and
   the background fills only the frame. Without a size or maximum of its own, the frame of content
   that expands only so far (LayoutCaps) stops at that cap, and an element in a bigger frame stops
   at its own cap and is aligned in it, as SwiftUI's views stop at their size. A height cap is
   measured at the frame's width, so text that wraps there counts with all its lines.
 - disabled makes the element's widget insensitive, which GTK passes on to its descendants.
 - offset, rotation and scale move what is drawn, not the layout, as in SwiftUI: offset first,
   then rotation around the center, then scale around its anchor.

 Known differences from the Apple renderer's order (View.applyModifiers):
 - The border is a CSS outline on the content group, so it moves with offset, rotation and scale
   and follows a corner radius; SwiftUI's border stays at the layout frame and square. Drawing it
   by hand would lose the theme's colors for named border colors.
 - opacity fades the whole box, border and shadow included; on Apple it applies before the border
   and shadow, which stay unfaded. (hidden hides the whole element on every renderer.)
*/

import CAdwaita

/// What a box lays out, attached to the outer box and set by update.
@MainActor
final class BoxLayout {
    var padding = (horizontal: PaddingAxis(), vertical: PaddingAxis())
    var frame = (horizontal: FrameAxis.none, vertical: FrameAxis.none)
    var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)
    /// Offset, then rotation in degrees around the center, then scale around `scaleAnchor`.
    var offset = (x: 0.0, y: 0.0)
    var rotation = 0.0
    var scale = (x: 1.0, y: 1.0)
    var scaleAnchor = (x: 0.5, y: 0.5)

    func padding(_ orientation: GtkOrientation) -> PaddingAxis {
        orientation == GTK_ORIENTATION_HORIZONTAL ? padding.horizontal : padding.vertical
    }

    func frame(_ orientation: GtkOrientation) -> FrameAxis {
        orientation == GTK_ORIENTATION_HORIZONTAL ? frame.horizontal : frame.vertical
    }

    func alignment(_ orientation: GtkOrientation) -> StackSolver.Alignment {
        orientation == GTK_ORIENTATION_HORIZONTAL ? alignment.horizontal : alignment.vertical
    }

    var hasTransform: Bool {
        offset != (0, 0) || rotation != 0 || scale != (1, 1)
    }
}

/// The shadow a box draws, attached to the outer box.
@MainActor
final class BoxShadow {
    var shadow: GskShadow?
}

/// The accessibility values last given to an element's widget, attached to it.
@MainActor
final class AccessibilityState {
    var label: String?
    var hint: String?
    var hidden = false
    var identifier: String?
}

let boxLayoutKey = AttachKey<BoxLayout>("actionui-box")
let boxShadowKey = AttachKey<BoxShadow>("actionui-shadow")
let accessibilityStateKey = AttachKey<AccessibilityState>("actionui-accessibility")

nonisolated(unsafe) private var boxLayoutType: GType = 0
nonisolated(unsafe) private var contentLayoutType: GType = 0
nonisolated(unsafe) private var boxWidgetType: GType = 0
nonisolated(unsafe) private var boxParentClass: UnsafeMutablePointer<GtkWidgetClass>?
nonisolated(unsafe) private var contentGroupType: GType = 0
nonisolated(unsafe) private var contentParentClass: UnsafeMutablePointer<GtkWidgetClass>?

@MainActor
enum ModifierBox {
    /// SwiftUI's shadow color when none is given (ColorHelper.defaultShadowColor).
    static let defaultShadowColor = GdkRGBA(red: 0, green: 0, blue: 0, alpha: 0.33)

    /// A new box holding `widget` in its content group. The box carries the widget's
    /// SpacerMarker, so its stack treats the box as the Spacer.
    static func wrap(_ widget: WidgetPointer) -> WidgetPointer {
        let box: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(boxType(), 0, nil, nil)!))
        let manager: UnsafeMutablePointer<GtkLayoutManager> = typed(OpaquePointer(g_object_new_with_properties(layoutType(), 0, nil, nil)!))
        gtk_widget_set_layout_manager(box, manager)
        attach(BoxLayout(), to: box, key: boxLayoutKey)
        attach(BoxShadow(), to: box, key: boxShadowKey)
        if let marker = attached(on: widget, key: spacerMarkerKey) {
            attach(marker, to: box, key: spacerMarkerKey)
        }
        let content: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(contentWidgetType(), 0, nil, nil)!))
        let contentManager: UnsafeMutablePointer<GtkLayoutManager> = typed(OpaquePointer(g_object_new_with_properties(contentType(), 0, nil, nil)!))
        gtk_widget_set_layout_manager(content, contentManager)
        gtk_widget_set_parent(content, box)
        gtk_widget_set_parent(widget, content)
        return box
    }

    /// The content group of a box: the widget between the box and the element's widget.
    static func content(of box: WidgetPointer) -> WidgetPointer? {
        Gtk.Widget(box).firstChild?.pointer
    }

    /// Applies the node's base modifiers to its box, its content group and its widget.
    static func update(_ box: WidgetPointer, _ node: RenderNode, _ modifiers: BaseModifiers) {
        let widget: WidgetPointer = node.widget
        applyBoxModifiers(box, modifiers)
        applyText(widget, modifiers)
        applyAccessibility(widget, node, modifiers)

        Gtk.Widget(widget).isSensitive = modifiers.disabled != true
        let help = modifiers.help.flatMap { $0.isEmpty ? nil : $0 }
        if swiftString(gtk_widget_get_tooltip_text(widget)) != help {
            gtk_widget_set_tooltip_text(widget, help)
        }
    }

    /// Applies what the box itself draws and lays out: padding, frame, paint, shadow, effects,
    /// opacity and hidden. A Group's box around each of its children takes these from the Group
    /// (Group+Adwaita), as SwiftUI applies a Group's modifiers to each child.
    static func applyBoxModifiers(_ box: WidgetPointer, _ modifiers: BaseModifiers) {
        applyLayout(box, modifiers)
        if let content = content(of: box) {
            applyPaint(content, modifiers)
        }
        applyShadow(box, modifiers.shadow)
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
    }

    // MARK: Layout settings

    private static func applyLayout(_ box: WidgetPointer, _ modifiers: BaseModifiers) {
        guard let layout = attached(on: box, key: boxLayoutKey) else { return }
        let padding = paddingAxes(modifiers.padding)
        let frame = frameAxes(modifiers.frame)
        let alignment = alignmentAxes(modifiers.frame?.alignment)
        let offset = (x: finite(modifiers.offset?.x, 0), y: finite(modifiers.offset?.y, 0))
        let rotation = finite(modifiers.rotationDegrees, 0)
        let scale = (x: finite(modifiers.scale?.x, 1), y: finite(modifiers.scale?.y, 1))
        let anchor = unitPoint(modifiers.scale?.anchor ?? .center)
        let layoutChanged = layout.padding != padding || layout.frame != frame || layout.alignment != alignment
        let transformChanged = layout.offset != offset || layout.rotation != rotation || layout.scale != scale
            || layout.scaleAnchor != anchor
        guard layoutChanged || transformChanged else { return }
        layout.padding = padding
        layout.frame = frame
        layout.alignment = alignment
        layout.offset = offset
        layout.rotation = rotation
        layout.scale = scale
        layout.scaleAnchor = anchor
        setExpand(box, GTK_ORIENTATION_HORIZONTAL, frame.horizontal.expands)
        setExpand(box, GTK_ORIENTATION_VERTICAL, frame.vertical.expands)
        if layoutChanged {
            gtk_widget_queue_resize(box)
            if let content = content(of: box) {
                gtk_widget_queue_resize(content)
            }
        } else {
            gtk_widget_queue_allocate(box)
        }
    }

    private static func finite(_ value: Double?, _ fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return value
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

    /// An anchor name as a unit point: (0, 0) top leading, (1, 1) bottom trailing.
    static func unitPoint(_ name: BaseModifiers.AlignmentName) -> (x: Double, y: Double) {
        let axes = alignmentAxes(name)
        func fraction(_ alignment: StackSolver.Alignment) -> Double {
            switch alignment {
            case .start: return 0
            case .center: return 0.5
            case .end: return 1
            }
        }
        return (fraction(axes.horizontal), fraction(axes.vertical))
    }

    // MARK: Painting

    /// The content group's background, rounding and clip, and border.
    private static func applyPaint(_ content: WidgetPointer, _ modifiers: BaseModifiers) {
        let background = modifiers.background.flatMap(ShapeStyleSpec.parse).map {
            ["background-color: \(ColorCSS.value($0));"]
        } ?? []
        StyleSheet.shared.apply(background, to: content, slot: "background")

        let radius = cornerRadius(modifiers)
        StyleSheet.shared.apply(radius.map { ["border-radius: \($0);"] } ?? [], to: content, slot: "shape")
        let clips = radius != nil
        let overflow = clips ? GTK_OVERFLOW_HIDDEN : GTK_OVERFLOW_VISIBLE
        if gtk_widget_get_overflow(content) != overflow {
            gtk_widget_set_overflow(content, overflow)
        }

        var border: [String] = []
        if let spec = modifiers.border, spec.width.isFinite, spec.width > 0 {
            let width = FontCSS.pixels(spec.width)
            let color = ColorSpec.parse(spec.color).map(ColorCSS.value) ?? "#000000"
            // Inside the frame, as SwiftUI's border, drawn over the content.
            border = ["outline: \(width)px solid \(color);", "outline-offset: -\(width)px;"]
        }
        StyleSheet.shared.apply(border, to: content, slot: "border")
    }

    /// The CSS border-radius of cornerRadius and clipShape (clipShape wins, as it clips after),
    /// nil for neither. A circle in a frame that is not square is an ellipse here.
    static func cornerRadius(_ modifiers: BaseModifiers) -> String? {
        switch modifiers.clipShape {
        case .circle, .ellipse:
            return "50%"
        case .capsule:
            return "9999px"
        case .rectangle:
            // No rounding, but a clip to the frame (a non-nil result turns the clip on).
            return "0"
        case let .roundedRectangle(radiusX, radiusY):
            return "\(FontCSS.pixels(max(radiusX, 0.1)))px / \(FontCSS.pixels(max(radiusY, 0.1)))px"
        case nil:
            break
        }
        guard let radius = modifiers.cornerRadius, radius.isFinite, radius > 0 else { return nil }
        return "\(FontCSS.pixels(radius))px"
    }

    private static func applyShadow(_ box: WidgetPointer, _ shadow: BaseModifiers.Shadow?) {
        guard let state = attached(on: box, key: boxShadowKey) else { return }
        var next: GskShadow?
        if let shadow, shadow.radius.isFinite, shadow.x.isFinite, shadow.y.isFinite {
            let color = ColorSpec.parse(shadow.color).map { spec -> GdkRGBA in
                let value = ColorCSS.components(spec)
                return GdkRGBA(red: Float(value.red), green: Float(value.green), blue: Float(value.blue), alpha: Float(value.alpha))
            } ?? defaultShadowColor
            next = GskShadow(color: color, dx: Float(shadow.x), dy: Float(shadow.y),
                             radius: Float(min(max(shadow.radius, 0), 1000)))
        }
        let same: Bool
        switch (state.shadow, next) {
        case (nil, nil): same = true
        case let (old?, new?):
            same = old.dx == new.dx && old.dy == new.dy && old.radius == new.radius
                && old.color.red == new.color.red && old.color.green == new.color.green
                && old.color.blue == new.color.blue && old.color.alpha == new.color.alpha
        default: same = false
        }
        guard !same else { return }
        state.shadow = next
        gtk_widget_queue_draw(box)
    }

    /// The element widget's font, foreground color and tint, which its descendants inherit.
    private static func applyText(_ widget: WidgetPointer, _ modifiers: BaseModifiers) {
        if let value = modifiers.font {
            let style = FontCSS.style(FontSpec.parse(value, logger: ActionUIModel.shared.logger))
            StyleSheet.shared.apply(style.declarations, named: style.classes, to: widget, slot: "font")
        } else {
            StyleSheet.shared.apply([], to: widget, slot: "font")
        }
        let foreground = modifiers.foregroundStyle.flatMap(ShapeStyleSpec.parse).map { ["color: \(ColorCSS.value($0));"] } ?? []
        StyleSheet.shared.apply(foreground, to: widget, slot: "foreground")
        // libadwaita's accent: controls draw with --accent-bg-color, text and links with
        // --accent-color.
        let tint = modifiers.tint.flatMap(ShapeStyleSpec.parse).map { style -> [String] in
            let value = ColorCSS.value(style)
            return ["--accent-bg-color: \(value);", "--accent-color: \(value);"]
        } ?? []
        StyleSheet.shared.apply(tint, to: widget, slot: "tint")
    }

    // MARK: Accessibility

    /// The element's accessible name (accessibilityLabel, else the renderer's default name) and
    /// hint, written to the renderer's accessible widget; its hidden state (accessibilityHidden,
    /// or hidden, which keeps it out of the tree as on Apple and Android) and its identifier,
    /// which GTK has no property for: it becomes the widget's name, which test tools and the
    /// inspector show.
    private static func applyAccessibility(_ widget: WidgetPointer, _ node: RenderNode, _ modifiers: BaseModifiers) {
        let state: AccessibilityState
        if let existing = attached(on: widget, key: accessibilityStateKey) {
            state = existing
        } else {
            state = AccessibilityState()
            attach(state, to: widget, key: accessibilityStateKey)
        }
        let accessible = OpaquePointer(widget)
        let named = OpaquePointer(node.renderer.accessibleWidget(widget))
        // A label or hint is written on every update, not only when it changed: a widget can
        // write the same properties itself (GtkLabel sets its label from its text), and GTK
        // ignores a write of the value it already has. Only the reset depends on the last value.
        let label = [modifiers.accessibilityLabel, node.renderer.defaultAccessibleLabel(node)]
            .compactMap { $0 }.first { !$0.isEmpty }
        if label != nil || state.label != nil {
            state.label = label
            setString(named, GTK_ACCESSIBLE_PROPERTY_LABEL, label)
        }
        // The hint, else the help text, which SwiftUI's .help also gives assistive technologies.
        let hint = [modifiers.accessibilityHint, modifiers.help].compactMap { $0 }.first { !$0.isEmpty }
        if hint != nil || state.hint != nil {
            state.hint = hint
            setString(named, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, hint)
        }
        let hidden = modifiers.hidden || modifiers.accessibilityHidden == true
        if state.hidden != hidden {
            state.hidden = hidden
            // Shown again: the state GTK keeps itself, hidden while unmapped.
            setHidden(accessible, hidden || gtk_widget_get_mapped(widget) == 0)
        }
        let identifier = modifiers.accessibilityIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        if state.identifier != identifier {
            state.identifier = identifier
            // nil restores the default name, the widget's type name (as the name property's
            // default, NULL, does).
            gtk_widget_set_name(widget, identifier)
        }
    }

    /// Sets the hidden state.
    private static func setHidden(_ accessible: OpaquePointer, _ hidden: Bool) {
        var value = GValue()
        gtk_accessible_state_init_value(GTK_ACCESSIBLE_STATE_HIDDEN, &value)
        g_value_set_boolean(&value, hidden ? 1 : 0)
        var name = GTK_ACCESSIBLE_STATE_HIDDEN
        gtk_accessible_update_state_value(accessible, 1, &name, &value)
        g_value_unset(&value)
    }

    /// GTK sets a widget's hidden state to false whenever it maps, after its map handlers run, so
    /// the content group hides its element again once it has mapped it (the element maps inside
    /// the content group's map).
    private static func contentMapped(_ content: WidgetPointer) {
        guard let widget = Gtk.Widget(content).firstChild?.pointer,
              attached(on: widget, key: accessibilityStateKey)?.hidden == true else { return }
        setHidden(OpaquePointer(widget), true)
    }

    /// Sets a string accessibility property, or resets it for nil.
    private static func setString(_ accessible: OpaquePointer, _ property: GtkAccessibleProperty, _ text: String?) {
        guard let text else {
            gtk_accessible_reset_property(accessible, property)
            return
        }
        var value = GValue()
        gtk_accessible_property_init_value(property, &value)
        g_value_set_string(&value, text)
        var name = property
        gtk_accessible_update_property_value(accessible, 1, &name, &value)
        g_value_unset(&value)
    }

    // MARK: The widgets and layout managers

    /// The content group: a container with no meaning to assistive technologies, which keeps a
    /// hidden element hidden from them when it maps.
    static func contentWidgetType() -> GType {
        if contentGroupType != 0 { return contentGroupType }
        let parent = actionUIContainerType()
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            contentParentClass = g_type_class_peek_parent(klass)?.assumingMemoryBound(to: GtkWidgetClass.self)
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.map = { widget in
                guard let widget else { return }
                contentParentClass?.pointee.map?(widget)
                MainActor.assumeIsolated { ModifierBox.contentMapped(widget) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-content")
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_GENERIC)
        }
        contentGroupType = g_type_register_static(parent, "ActionUIContentGroup", &info, GTypeFlags(0))
        return contentGroupType
    }

    /// The outer box: a container that draws its content with the box's shadow.
    static func boxType() -> GType {
        if boxWidgetType != 0 { return boxWidgetType }
        let parent = actionUIContainerType()
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            boxParentClass = g_type_class_peek_parent(klass)?.assumingMemoryBound(to: GtkWidgetClass.self)
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let widget, let snapshot else { return }
                MainActor.assumeIsolated { ModifierBox.snapshot(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-box")
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_GENERIC)
        }
        boxWidgetType = g_type_register_static(parent, "ActionUIModifierBox", &info, GTypeFlags(0))
        return boxWidgetType
    }

    private static func snapshot(_ box: WidgetPointer, _ snapshot: OpaquePointer) {
        let drawChildren = { boxParentClass?.pointee.snapshot?(box, snapshot) }
        guard var shadow = attached(on: box, key: boxShadowKey)?.shadow else {
            drawChildren()
            return
        }
        gtk_snapshot_push_shadow(snapshot, &shadow, 1)
        drawChildren()
        gtk_snapshot_pop(snapshot)
    }

    /// The outer box's layout: the frame, centered when the box is bigger, with the transform.
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
                let size = MainActor.assumeIsolated { ModifierBox.measureBox(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { ModifierBox.allocateBox(widget, width: Int(width), height: Int(height)) }
            }
        }
        boxLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIModifierLayout", &info, GTypeFlags(0))
        return boxLayoutType
    }

    /// The content group's layout: the padding, and the element aligned in what is left.
    static func contentType() -> GType {
        if contentLayoutType != 0 { return contentLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { ModifierBox.measureContent(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { ModifierBox.allocateContent(widget, width: Int(width), height: Int(height)) }
            }
        }
        contentLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIContentLayout", &info, GTypeFlags(0))
        return contentLayoutType
    }

    // MARK: Measuring and placing

    private static func layout(ofBox box: WidgetPointer) -> BoxLayout {
        attached(on: box, key: boxLayoutKey) ?? BoxLayout()
    }

    /// The BoxLayout of the box a content group is in.
    private static func layout(ofContent content: WidgetPointer) -> BoxLayout {
        gtk_widget_get_parent(content).map { layout(ofBox: $0) } ?? BoxLayout()
    }

    private static func measureChild(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> Gtk.Measurement {
        Gtk.Widget(child).measure(orientation, forSize: forSize)
    }

    /// The frame's size in one axis when the box is `boxSize`: what the frame takes of it (a
    /// parent may give more than the frame asked for). Without a size or maximum of its own, a
    /// frame of content that expands only so far (a VStack of capped children, a
    /// ContentUnavailableView) stops at the box's cap, as SwiftUI's view stops at its own size, so
    /// the background, border and shadow stop there too and the frame is centered in the rest.
    private static func frameSize(_ box: WidgetPointer, _ content: WidgetPointer, _ layout: BoxLayout,
                                  _ orientation: GtkOrientation, boxSize: Int, forSize: Int = -1) -> Int {
        let measured = measureChild(content, orientation, forSize: forSize)
        let frame = layout.frame(orientation)
        let expands = Gtk.Widget(content).expands(orientation)
        let size = frame.size(in: boxSize, contentMinimum: measured.minimum, contentNatural: measured.natural,
                              contentExpands: expands)
        guard expands, frame.fixed == nil, frame.maximum == nil,
              let cap = LayoutCaps.cap(box, orientation, forSize: forSize) else {
            return size
        }
        return max(min(size, cap), frame.minimumSize(content: measured.minimum))
    }

    /// The element's width when its box is `width` wide, as allocateBox and allocateContent give
    /// it (LayoutCaps measures the element's height cap at it).
    static func elementWidth(inBox box: WidgetPointer, width: Int) -> Int {
        guard let content = layoutChildren(box).first, let element = layoutChildren(content).first else { return width }
        let layout = layout(ofBox: box)
        let frameWidth = frameSize(box, content, layout, GTK_ORIENTATION_HORIZONTAL, boxSize: width)
        return elementSize(element, layout, GTK_ORIENTATION_HORIZONTAL, size: frameWidth)
    }

    /// Where the element starts in a box `width` wide, and its width, as allocateBox and
    /// allocateContent place it: the frame centered in the box, the padding before, the element
    /// aligned in the padded frame (FormLayout finds a title's trailing edge through the boxes
    /// around its row). The box's offset, rotation and scale move no layout.
    static func elementPlacement(inBox box: WidgetPointer, width: Int) -> (start: Int, width: Int) {
        guard let content = layoutChildren(box).first, let element = layoutChildren(content).first else { return (0, width) }
        let layout = layout(ofBox: box)
        let frameWidth = frameSize(box, content, layout, GTK_ORIENTATION_HORIZONTAL, boxSize: width)
        let elementWidth = elementSize(element, layout, GTK_ORIENTATION_HORIZONTAL, size: frameWidth)
        let padding = layout.padding.horizontal
        let start = StackSolver.centeredStart(length: frameWidth, available: width) + padding.before
            + StackSolver.alignedOffset(size: elementWidth, block: frameWidth - padding.total, alignment: layout.alignment.horizontal)
        return (start, elementWidth)
    }

    static func measureBox(_ box: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let content = layoutChildren(box).first else { return (0, 0) }
        let layout = layout(ofBox: box)
        // Height for width: the content group's height at the frame's width in a box that wide.
        var contentForSize = -1
        if forSize >= 0, orientation == GTK_ORIENTATION_VERTICAL {
            contentForSize = frameSize(box, content, layout, GTK_ORIENTATION_HORIZONTAL, boxSize: forSize)
        }
        let measured = measureChild(content, orientation, forSize: contentForSize)
        let frame = layout.frame(orientation)
        return (frame.minimumSize(content: measured.minimum),
                frame.naturalSize(content: measured.natural, contentMinimum: measured.minimum))
    }

    static func allocateBox(_ box: WidgetPointer, width: Int, height: Int) {
        guard let content = layoutChildren(box).first else { return }
        // A Group whose stack lays its children out as its own spans the stack (Group+Adwaita).
        if let element = layoutChildren(content).first, Group.isFlattened(element) {
            allocateWhole(content, width: width, height: height)
            return
        }
        let layout = layout(ofBox: box)
        let frame = contentFrame(box, width: width, height: height)
        var origin = graphene_point_t(x: Float(frame.x), y: Float(frame.y))
        var transform = gsk_transform_translate(nil, &origin)
        if layout.hasTransform {
            transform = applyEffects(transform, layout, width: Double(frame.width), height: Double(frame.height))
        }
        gtk_widget_allocate(content, Int32(clamping: frame.width), Int32(clamping: frame.height), -1, transform)
    }

    /// Where the content group (the frame) is in a box `width` x `height`, and its size, as
    /// allocateBox places it: centered in a box bigger than it, as SwiftUI's parent centers it.
    /// The box's offset, rotation and scale move no layout. Baselines reads it too.
    static func contentFrame(_ box: WidgetPointer, width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        guard let content = layoutChildren(box).first else { return (0, 0, width, height) }
        let layout = layout(ofBox: box)
        let frameWidth = frameSize(box, content, layout, GTK_ORIENTATION_HORIZONTAL, boxSize: width)
        let frameHeight = frameSize(box, content, layout, GTK_ORIENTATION_VERTICAL, boxSize: height, forSize: frameWidth)
        return (StackSolver.centeredStart(length: frameWidth, available: width),
                StackSolver.centeredStart(length: frameHeight, available: height), frameWidth, frameHeight)
    }

    /// Gives `child` the whole `width` x `height` at its parent's origin (measured first, as GTK
    /// expects of an allocated widget).
    private static func allocateWhole(_ child: WidgetPointer, width: Int, height: Int) {
        _ = measureChild(child, GTK_ORIENTATION_HORIZONTAL, forSize: -1)
        _ = measureChild(child, GTK_ORIENTATION_VERTICAL, forSize: width)
        gtk_widget_allocate(child, Int32(clamping: width), Int32(clamping: height), -1, nil)
    }

    /// Scale around its anchor, rotation around the center, and the offset, composed so a point
    /// of the content is offset first, then rotated, then scaled, as SwiftUI applies them.
    private static func applyEffects(_ start: OpaquePointer?, _ layout: BoxLayout, width: Double, height: Double) -> OpaquePointer? {
        var transform = start
        if layout.scale != (1, 1) {
            var anchor = graphene_point_t(x: Float(width * layout.scaleAnchor.x), y: Float(height * layout.scaleAnchor.y))
            var back = graphene_point_t(x: -anchor.x, y: -anchor.y)
            transform = gsk_transform_translate(transform, &anchor)
            transform = gsk_transform_scale(transform, Float(layout.scale.x), Float(layout.scale.y))
            transform = gsk_transform_translate(transform, &back)
        }
        if layout.rotation != 0 {
            var center = graphene_point_t(x: Float(width / 2), y: Float(height / 2))
            var back = graphene_point_t(x: -center.x, y: -center.y)
            transform = gsk_transform_translate(transform, &center)
            transform = gsk_transform_rotate(transform, Float(layout.rotation))
            transform = gsk_transform_translate(transform, &back)
        }
        if layout.offset != (0, 0) {
            var offset = graphene_point_t(x: Float(layout.offset.x), y: Float(layout.offset.y))
            transform = gsk_transform_translate(transform, &offset)
        }
        return transform
    }

    /// The element's size in one axis in a content group of `size`: offered the size less the
    /// padding, clamped to its own range, up to its cap when it expands (a frame bigger than a
    /// capped VStack centers the VStack, as SwiftUI's frame does, rather than widening it).
    private static func elementSize(_ element: WidgetPointer, _ layout: BoxLayout, _ orientation: GtkOrientation,
                                    size: Int, forSize: Int = -1) -> Int {
        let measured = measureChild(element, orientation, forSize: forSize)
        let expands = Gtk.Widget(element).expands(orientation)
        let cap = expands ? LayoutCaps.cap(element, orientation, forSize: forSize) : nil
        return FrameSolver.contentSize(in: size, padding: layout.padding(orientation), minimum: measured.minimum,
                                       natural: measured.natural, expands: expands, cap: cap)
    }

    static func measureContent(_ content: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let element = layoutChildren(content).first else { return (0, 0) }
        let layout = layout(ofContent: content)
        var elementForSize = -1
        if forSize >= 0, orientation == GTK_ORIENTATION_VERTICAL {
            elementForSize = elementSize(element, layout, GTK_ORIENTATION_HORIZONTAL, size: forSize)
        }
        let measured = measureChild(element, orientation, forSize: elementForSize)
        let padding = layout.padding(orientation).total
        // Negative padding can take the padded size below 0; GTK sizes are never negative.
        return (max(measured.minimum + padding, 0), max(measured.natural + padding, 0))
    }

    static func allocateContent(_ content: WidgetPointer, width: Int, height: Int) {
        guard let element = layoutChildren(content).first else { return }
        if Group.isFlattened(element) {
            allocateWhole(element, width: width, height: height)
            return
        }
        let frame = elementFrame(content, width: width, height: height)
        var origin = graphene_point_t(x: Float(frame.x), y: Float(frame.y))
        gtk_widget_allocate(element, Int32(clamping: frame.width), Int32(clamping: frame.height), -1,
                            gsk_transform_translate(nil, &origin))
    }

    /// Where the element is in a content group `width` x `height`, and its size, as
    /// allocateContent places it: after the padding, aligned in what is left by the frame's
    /// alignment. Baselines reads it too.
    static func elementFrame(_ content: WidgetPointer, width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        guard let element = layoutChildren(content).first else { return (0, 0, width, height) }
        let layout = layout(ofContent: content)
        let elementWidth = elementSize(element, layout, GTK_ORIENTATION_HORIZONTAL, size: width)
        let elementHeight = elementSize(element, layout, GTK_ORIENTATION_VERTICAL, size: height, forSize: elementWidth)
        let horizontal = layout.padding.horizontal
        let vertical = layout.padding.vertical
        let x = horizontal.before + StackSolver.alignedOffset(size: elementWidth, block: width - horizontal.total,
                                                             alignment: layout.alignment.horizontal)
        let y = vertical.before + StackSolver.alignedOffset(size: elementHeight, block: height - vertical.total,
                                                           alignment: layout.alignment.vertical)
        return (x, y, elementWidth, elementHeight)
    }
}
