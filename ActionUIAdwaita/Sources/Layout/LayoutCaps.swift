// Sources/Layout/LayoutCaps.swift
/*
 How far a widget expands: the largest size it takes in an axis when offered any amount, which is
 SwiftUI's size of a view offered infinity. A stack offers its expanding children space up to
 that, so a VStack holding a child framed to maxWidth 200 stops at 200 like its child, and a
 Spacer beside it gets the rest.

 - A ModifierBox: its frame's maximum; without one, its content's cap plus the padding, and at
   least the frame's minimum.
 - A VStack or HStack: along its axis, the sum of its children's largest sizes plus the spacing
   between them; across it, the largest of its children's.
 - A ZStack: the largest of its children's, in each axis.
 - A child's largest size is its cap where it expands and its natural size where it does not.
 - nil: unbounded. That is any other widget that expands (a Color, a Spacer), and any container
   with an unbounded child in that axis.
*/

import CAdwaita

@MainActor
enum LayoutCaps {
    /// The largest size `widget` takes in `orientation` when it expands; nil when unbounded.
    static func cap(_ widget: WidgetPointer, _ orientation: GtkOrientation) -> Int? {
        if let box = attached(BoxLayout.self, on: widget, key: boxLayoutKey) {
            return boxCap(widget, box, orientation)
        }
        if let stack = attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) {
            return stackCap(widget, stack, orientation)
        }
        if attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) != nil {
            return largestOfChildren(widget, orientation)
        }
        return nil
    }

    /// The largest size a child takes: its cap where it expands, its natural size where not.
    static func largestSize(_ child: WidgetPointer, _ orientation: GtkOrientation) -> Int? {
        if gtk_widget_compute_expand(child, orientation) != 0 {
            return cap(child, orientation)
        }
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(child, orientation, -1, &minimum, &natural, nil, nil)
        return Int(natural)
    }

    private static func boxCap(_ box: WidgetPointer, _ layout: BoxLayout, _ orientation: GtkOrientation) -> Int? {
        let frame = layout.frame(orientation)
        if let fixed = frame.fixed {
            return fixed
        }
        if let maximum = frame.maximum {
            return maximum == FrameAxis.infinity ? nil : maximum
        }
        guard let child = layoutChildren(box).first,
              let content = largestSize(child, orientation) else { return nil }
        let padded = content + layout.padding(orientation).total
        return frame.minimum.map { max(padded, $0) } ?? padded
    }

    private static func stackCap(_ widget: WidgetPointer, _ stack: StackConfiguration, _ orientation: GtkOrientation) -> Int? {
        let main = stack.axis == .vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        guard orientation == main else {
            return largestOfChildren(widget, orientation)
        }
        let children = layoutChildren(widget)
        var total = StackLayout.gaps(children, stack).reduce(0, +)
        for child in children {
            guard let size = largestSize(child, orientation) else { return nil }
            total += size
        }
        return total
    }

    private static func largestOfChildren(_ widget: WidgetPointer, _ orientation: GtkOrientation) -> Int? {
        var largest = 0
        for child in layoutChildren(widget) {
            guard let size = largestSize(child, orientation) else { return nil }
            largest = max(largest, size)
        }
        return largest
    }
}
