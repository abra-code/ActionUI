// Sources/Layout/StackLayout.swift
/*
 VStack and HStack on GTK: a GtkLayoutManager subclass, registered from Swift, that measures and
 places a container's children with StackSolver's arithmetic.

 - Cross axis: every child is offered the stack's cross size and takes it clamped to its range (a
   child that expands in that axis takes all of it, up to its frame's maximum). The children form
   a block as wide as the widest of them, centered in the stack; each child is aligned inside the
   block by the stack's alignment, so VStack(alignment: .leading) aligns to the stack's leading
   edge, not the window's.
 - Main axis: StackSolver.mainSizes, the group centered when it does not fill the stack. Spacers
   (SpacerMarker on the child) come last and get no default spacing, as in SwiftUI.
 - Height for width: a VStack's children are measured for the width they get, and an HStack's
   height is measured for the widths it gives its children, so wrapping text gets taller in a
   narrower stack.
 - A child expands where GTK's computed expand flag says so (set by its renderer, or by its frame
   through its modifier box, and propagated from its own children as in SwiftUI), up to the cap
   LayoutCaps finds for it: its frame's maximum, or what its own children take at most.
*/

import CAdwaita

/// A stack's axis.
enum StackAxis {
    case vertical, horizontal
}

/// A stack's settings, attached to its container widget; the renderer's update sets them.
@MainActor
final class StackConfiguration {
    var axis: StackAxis
    var spacing: Int
    /// The stack was given no spacing (SwiftUI's default): there is none next to a Spacer.
    var isDefaultSpacing: Bool
    var alignment: StackSolver.Alignment

    init(axis: StackAxis, spacing: Int, isDefaultSpacing: Bool, alignment: StackSolver.Alignment) {
        self.axis = axis
        self.spacing = spacing
        self.isDefaultSpacing = isDefaultSpacing
        self.alignment = alignment
    }
}

/// Attached to a Spacer's widget: its stack places it after the other children and puts no
/// default spacing next to it (StackChild.isSpacer). A box wrapping a Spacer must carry it too.
@MainActor
final class SpacerMarker {}

let stackConfigurationKey = "actionui-stack"
let spacerMarkerKey = "actionui-spacer"

nonisolated(unsafe) private var stackLayoutType: GType = 0

@MainActor
enum StackLayout {
    /// SwiftUI's usual spacing between controls, for a stack that gives none.
    static let defaultSpacing = 8.0

    /// A new, empty stack container.
    static func makeStack(axis: StackAxis) -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        attach(StackConfiguration(axis: axis, spacing: 0, isDefaultSpacing: false, alignment: .center),
               to: widget, key: stackConfigurationKey)
        return widget
    }

    /// Sets a stack's spacing (nil: SwiftUI's default, none next to a Spacer) and alignment,
    /// relaying it out only when they changed.
    static func configure(_ widget: WidgetPointer, spacing: Double?, alignment: StackSolver.Alignment) {
        guard let configuration = attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) else { return }
        let points = StackSolver.length(spacing ?? defaultSpacing)
        let isDefault = spacing == nil
        guard configuration.spacing != points || configuration.isDefaultSpacing != isDefault
                || configuration.alignment != alignment else { return }
        configuration.spacing = points
        configuration.isDefaultSpacing = isDefault
        configuration.alignment = alignment
        gtk_widget_queue_resize(widget)
    }

    static func layoutType() -> GType {
        if stackLayoutType != 0 { return stackLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { StackLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { StackLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        stackLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIStackLayout", &info, GTypeFlags(0))
        return stackLayoutType
    }

    // MARK: Measuring children

    private struct Measured {
        var minimum: Int
        var natural: Int
    }

    private static func measureChild(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int = -1) -> Measured {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(child, orientation, Int32(clamping: forSize), &minimum, &natural, nil, nil)
        return Measured(minimum: Int(minimum), natural: Int(natural))
    }

    /// A child as StackSolver sees it in one axis, measured for `forSize` in the other.
    private static func stackChild(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int = -1) -> StackChild {
        let size = measureChild(child, orientation, forSize: forSize)
        var result: StackChild
        if gtk_widget_compute_expand(child, orientation) != 0 {
            result = .expanding(minimum: size.minimum, cap: LayoutCaps.cap(child, orientation, forSize: forSize))
        } else {
            result = .fixed(minimum: size.minimum, natural: size.natural)
        }
        result.isSpacer = isSpacer(child)
        return result
    }

    private static func isSpacer(_ child: WidgetPointer) -> Bool {
        attached(SpacerMarker.self, on: child, key: spacerMarkerKey) != nil
    }

    /// The spacing between the stack's neighboring children (none next to a Spacer when the stack
    /// was given no spacing).
    static func gaps(_ children: [WidgetPointer], _ stack: StackConfiguration) -> [Int] {
        let marks = children.map { StackChild(minimum: 0, maximum: nil, isSpacer: isSpacer($0)) }
        return StackSolver.gaps(marks, spacing: stack.spacing, isDefaultSpacing: stack.isDefaultSpacing)
    }

    private static func configuration(_ widget: WidgetPointer) -> StackConfiguration {
        attached(StackConfiguration.self, on: widget, key: stackConfigurationKey)
            ?? StackConfiguration(axis: .vertical, spacing: 0, isDefaultSpacing: false, alignment: .center)
    }

    private static func orientations(_ axis: StackAxis) -> (main: GtkOrientation, cross: GtkOrientation) {
        axis == .vertical
            ? (GTK_ORIENTATION_VERTICAL, GTK_ORIENTATION_HORIZONTAL)
            : (GTK_ORIENTATION_HORIZONTAL, GTK_ORIENTATION_VERTICAL)
    }

    /// Each of `children`'s widths when the stack is `width` wide, as allocate gives them: a
    /// VStack offers each its width (less its offset in a Form), an HStack shares the width out
    /// along its axis.
    static func childWidths(_ widget: WidgetPointer, _ children: [WidgetPointer], width: Int) -> [Int] {
        let stack = configuration(widget)
        if stack.axis == .vertical {
            return verticalChildWidths(children, offsets: leadingOffsets(widget, children), width: width)
        }
        let widths = children.map { stackChild($0, GTK_ORIENTATION_HORIZONTAL) }
        return StackSolver.mainSizes(widths, available: width, gaps: gaps(children, stack))
    }

    /// A VStack's children's widths when it is `width` wide: each is offered the width less its
    /// offset.
    private static func verticalChildWidths(_ children: [WidgetPointer], offsets: [Int], width: Int) -> [Int] {
        children.enumerated().map { stackChild($1, GTK_ORIENTATION_HORIZONTAL).size(offered: width - offsets[$0]) }
    }

    /// Where each of `children` starts across a stack `width` wide, and its width, as allocate
    /// places it: an HStack's one after another, centered as a group; a VStack's in a block as
    /// wide as the widest of them (from its offset in a Form), centered, each aligned in the block
    /// by the stack's alignment. FormLayout reads it to find the titles inside a row.
    static func horizontalPlacements(_ widget: WidgetPointer, _ children: [WidgetPointer], width: Int) -> [(x: Int, width: Int)] {
        let stack = configuration(widget)
        if stack.axis == .horizontal {
            let gaps = Self.gaps(children, stack)
            let widths = StackSolver.mainSizes(children.map { stackChild($0, GTK_ORIENTATION_HORIZONTAL) }, available: width, gaps: gaps)
            var x = StackSolver.centeredStart(length: StackSolver.length(of: widths, gaps: gaps), available: width)
            return widths.enumerated().map { index, size in
                defer { x += size + (index < gaps.count ? gaps[index] : 0) }
                return (x, size)
            }
        }
        let offsets = leadingOffsets(widget, children)
        let widths = verticalChildWidths(children, offsets: offsets, width: width)
        let block = zip(offsets, widths).map(+).max() ?? 0
        let blockStart = StackSolver.centeredStart(length: block, available: width)
        return widths.indices.map { index in
            let aligned = StackSolver.alignedOffset(size: widths[index], block: block - offsets[index], alignment: stack.alignment)
            return (blockStart + offsets[index] + aligned, widths[index])
        }
    }

    /// Each child's leading offset: after a Form's label column (FormLayout), else 0.
    static func leadingOffsets(_ widget: WidgetPointer, _ children: [WidgetPointer]) -> [Int] {
        FormLayout.offsets(widget, children) ?? Array(repeating: 0, count: children.count)
    }

    // MARK: Measure

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> Measured {
        // A Group's widget whose stack places its children takes no size of its own: its box is
        // given the whole stack, which may be smaller than its children stacked (an HStack's
        // height), and GTK (with consistency checks) refuses an allocation below the minimum.
        if Group.isFlattened(widget) { return Measured(minimum: 0, natural: 0) }
        let stack = configuration(widget)
        let children = stackChildren(widget)
        guard !children.isEmpty else { return Measured(minimum: 0, natural: 0) }
        let (main, cross) = orientations(stack.axis)
        let gaps = Self.gaps(children, stack)
        // Height for width: the children's heights at the widths the stack gives them (a VStack
        // offers each its width, an HStack shares it out).
        var forSizes = Array(repeating: -1, count: children.count)
        if orientation == GTK_ORIENTATION_VERTICAL, forSize >= 0 {
            forSizes = childWidths(widget, children, width: forSize)
        }

        if orientation == main {
            let spacing = gaps.reduce(0, +)
            var total = Measured(minimum: spacing, natural: spacing)
            for (index, child) in children.enumerated() {
                let size = measureChild(child, main, forSize: forSizes[index])
                total.minimum += size.minimum
                total.natural += size.natural
            }
            return total
        }

        // Cross axis: the widest child, from its offset in a Form.
        let offsets = cross == GTK_ORIENTATION_HORIZONTAL
            ? leadingOffsets(widget, children) : Array(repeating: 0, count: children.count)
        var total = Measured(minimum: 0, natural: 0)
        for (index, child) in children.enumerated() {
            let size = measureChild(child, cross, forSize: forSizes[index])
            total.minimum = max(total.minimum, offsets[index] + size.minimum)
            total.natural = max(total.natural, offsets[index] + size.natural)
        }
        return total
    }

    // MARK: Allocate

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        // A Group's widget whose stack places its children: nothing to place here.
        if Group.isFlattened(widget) { return }
        Group.allocateGroups(in: widget, width: width, height: height)
        let stack = configuration(widget)
        let children = stackChildren(widget)
        guard !children.isEmpty else { return }
        let gaps = Self.gaps(children, stack)

        // The widths and places across first (a Form's rows start at their offsets, FormLayout);
        // the children's heights depend on their widths.
        let placements = horizontalPlacements(widget, children, width: width)
        var heights: [Int]
        var ys: [Int]
        if stack.axis == .vertical {
            let rows = children.enumerated().map { stackChild($1, GTK_ORIENTATION_VERTICAL, forSize: placements[$0].width) }
            heights = StackSolver.mainSizes(rows, available: height, gaps: gaps)
            var position = StackSolver.centeredStart(length: StackSolver.length(of: heights, gaps: gaps), available: height)
            ys = heights.enumerated().map { index, size in
                defer { position += size + (index < gaps.count ? gaps[index] : 0) }
                return position
            }
        } else {
            heights = children.enumerated().map {
                stackChild($1, GTK_ORIENTATION_VERTICAL, forSize: placements[$0].width).size(offered: height)
            }
            let block = heights.max() ?? 0
            let blockStart = StackSolver.centeredStart(length: block, available: height)
            ys = heights.map { blockStart + StackSolver.alignedOffset(size: $0, block: block, alignment: stack.alignment) }
        }
        for (index, child) in children.enumerated() {
            var origin = graphene_point_t(x: Float(placements[index].x), y: Float(ys[index]))
            gtk_widget_allocate(child, Int32(clamping: placements[index].width), Int32(clamping: heights[index]), -1,
                                gsk_transform_translate(nil, &origin))
        }
    }
}
