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
            result = .expanding(minimum: size.minimum, cap: LayoutCaps.cap(child, orientation))
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

    /// Each child's cross size when the stack's cross size is `available`.
    private static func crossSizes(_ children: [WidgetPointer], _ cross: GtkOrientation, available: Int) -> [Int] {
        children.map { stackChild($0, cross).size(offered: available) }
    }

    // MARK: Measure

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> Measured {
        let stack = configuration(widget)
        let children = layoutChildren(widget)
        guard !children.isEmpty else { return Measured(minimum: 0, natural: 0) }
        let (main, cross) = orientations(stack.axis)
        let gaps = Self.gaps(children, stack)

        if orientation == main {
            // A VStack's heights for a given width depend on the widths its children get.
            var forSizes = Array(repeating: -1, count: children.count)
            if main == GTK_ORIENTATION_VERTICAL, forSize >= 0 {
                forSizes = crossSizes(children, cross, available: forSize)
            }
            let spacing = gaps.reduce(0, +)
            var total = Measured(minimum: spacing, natural: spacing)
            for (index, child) in children.enumerated() {
                let size = measureChild(child, main, forSize: forSizes[index])
                total.minimum += size.minimum
                total.natural += size.natural
            }
            return total
        }

        // Cross axis. An HStack's height for a given width: the height of its children at the
        // widths the stack gives them.
        var forSizes = Array(repeating: -1, count: children.count)
        if cross == GTK_ORIENTATION_VERTICAL, forSize >= 0 {
            let widths = children.map { stackChild($0, main) }
            forSizes = StackSolver.mainSizes(widths, available: forSize, gaps: gaps)
        }
        var total = Measured(minimum: 0, natural: 0)
        for (index, child) in children.enumerated() {
            let size = measureChild(child, cross, forSize: forSizes[index])
            total.minimum = max(total.minimum, size.minimum)
            total.natural = max(total.natural, size.natural)
        }
        return total
    }

    // MARK: Allocate

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        let stack = configuration(widget)
        let children = layoutChildren(widget)
        guard !children.isEmpty else { return }
        let vertical = stack.axis == .vertical
        let (main, cross) = orientations(stack.axis)
        let mainAvailable = vertical ? height : width
        let crossAvailable = vertical ? width : height
        let gaps = Self.gaps(children, stack)

        // A VStack's widths first (its children's heights depend on them); an HStack's widths
        // are its main sizes, and its children's heights depend on those.
        var mainSizes: [Int]
        var crossSizes: [Int]
        if vertical {
            crossSizes = Self.crossSizes(children, cross, available: crossAvailable)
            let heights = children.enumerated().map { stackChild($1, main, forSize: crossSizes[$0]) }
            mainSizes = StackSolver.mainSizes(heights, available: mainAvailable, gaps: gaps)
        } else {
            let widths = children.map { stackChild($0, main) }
            mainSizes = StackSolver.mainSizes(widths, available: mainAvailable, gaps: gaps)
            crossSizes = children.enumerated().map {
                stackChild($1, cross, forSize: mainSizes[$0]).size(offered: crossAvailable)
            }
        }

        let block = crossSizes.max() ?? 0
        let blockStart = StackSolver.centeredStart(length: block, available: crossAvailable)
        var position = StackSolver.centeredStart(length: StackSolver.length(of: mainSizes, gaps: gaps),
                                                 available: mainAvailable)
        for (index, child) in children.enumerated() {
            let crossOffset = blockStart + StackSolver.alignedOffset(size: crossSizes[index], block: block,
                                                                     alignment: stack.alignment)
            var origin = vertical
                ? graphene_point_t(x: Float(crossOffset), y: Float(position))
                : graphene_point_t(x: Float(position), y: Float(crossOffset))
            let transform = gsk_transform_translate(nil, &origin)
            let childWidth = vertical ? crossSizes[index] : mainSizes[index]
            let childHeight = vertical ? mainSizes[index] : crossSizes[index]
            gtk_widget_allocate(child, Int32(clamping: childWidth), Int32(clamping: childHeight), -1, transform)
            position += mainSizes[index] + (index < gaps.count ? gaps[index] : 0)
        }
    }
}
