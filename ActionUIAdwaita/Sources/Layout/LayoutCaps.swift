// Sources/Layout/LayoutCaps.swift
/*
 How far a widget expands: the largest size it takes in an axis when offered any amount, which is
 SwiftUI's size of a view offered infinity. A stack offers its expanding children space up to
 that, so a VStack holding a child framed to maxWidth 200 stops at 200 like its child, and a
 Spacer beside it gets the rest.

 - A ModifierBox: its frame's maximum; without one, its element's cap plus the padding, and at
   least the frame's minimum.
 - A VStack or HStack: along its axis, the sum of its children's largest sizes plus the spacing
   between them; across it, the largest of its children's.
 - A ZStack: the largest of its children's, in each axis.
 - A GroupBox: its card's (its children's, as a VStack's, plus the padding) and its title's, one
   above the other (GroupBox.cap).
 - An element widget with a SizeLimit: that size (ContentUnavailableView is at most 400 points
   wide, as SwiftUI measures it).
 - A child's largest size is its cap where it expands and its natural size where it does not.
 - nil: unbounded. That is any other widget that expands (a Color, a Spacer), and any container
   with an unbounded child in that axis.
 - Height for width: a height cap may be asked for a given width. Each child is then measured at
   the width its container gives it in that width (as the container's allocate does), so text
   that wraps there counts with all its lines.
*/

import CAdwaita

/// Attached to an element's widget whose size has a largest value of its own in an axis, as
/// SwiftUI's ContentUnavailableView is at most 400 points wide: LayoutCaps finds it there.
@MainActor
final class SizeLimit {
    let width: Int?
    let height: Int?

    init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }
}

let sizeLimitKey = "actionui-size-limit"

@MainActor
enum LayoutCaps {
    /// The largest size `widget` takes in `orientation` when it expands; nil when unbounded. A
    /// height is for `forSize` wide (-1: no width given); a width ignores `forSize`.
    static func cap(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int = -1) -> Int? {
        let forSize = orientation == GTK_ORIENTATION_VERTICAL ? forSize : -1
        if let limit = attached(SizeLimit.self, on: widget, key: sizeLimitKey),
           let length = orientation == GTK_ORIENTATION_HORIZONTAL ? limit.width : limit.height {
            return length
        }
        if let box = attached(BoxLayout.self, on: widget, key: boxLayoutKey) {
            return boxCap(widget, box, orientation, forSize: forSize)
        }
        if let stack = attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) {
            return stackCap(widget, stack, orientation, forSize: forSize)
        }
        if attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) != nil {
            let widths = forSize >= 0 ? ZStackLayout.childWidths(widget, width: forSize) : nil
            return largestOfChildren(stackChildren(widget), orientation, widths: widths)
        }
        if attached(GroupBoxMarker.self, on: widget, key: groupBoxMarkerKey) != nil {
            return GroupBox.cap(widget, orientation, forSize: forSize)
        }
        return nil
    }

    /// The largest size a child takes: its cap where it expands, its natural size where not. A
    /// height is for `forSize` wide (-1: no width given).
    static func largestSize(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int = -1) -> Int? {
        if Gtk.Widget(child).expands(orientation) {
            return cap(child, orientation, forSize: forSize)
        }
        return Gtk.Widget(child).measure(orientation, forSize: forSize).natural
    }

    private static func boxCap(_ box: WidgetPointer, _ layout: BoxLayout, _ orientation: GtkOrientation, forSize: Int) -> Int? {
        let frame = layout.frame(orientation)
        if let fixed = frame.fixed {
            return fixed
        }
        if let maximum = frame.maximum {
            return maximum == FrameAxis.infinity ? nil : maximum
        }
        guard let group = ModifierBox.content(of: box), let element = layoutChildren(group).first else { return nil }
        let elementForSize = forSize >= 0 ? ModifierBox.elementWidth(inBox: box, width: forSize) : -1
        guard let content = largestSize(element, orientation, forSize: elementForSize) else { return nil }
        let padded = content + layout.padding(orientation).total
        return frame.minimum.map { max(padded, $0) } ?? padded
    }

    private static func stackCap(_ widget: WidgetPointer, _ stack: StackConfiguration, _ orientation: GtkOrientation,
                                 forSize: Int) -> Int? {
        let children = stackChildren(widget)
        let widths = forSize >= 0 ? StackLayout.childWidths(widget, children, width: forSize) : nil
        let main = stack.axis == .vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        guard orientation == main else {
            // Across a VStack: the widest child, from its offset in a Form (FormLayout).
            let offsets = orientation == GTK_ORIENTATION_HORIZONTAL ? StackLayout.leadingOffsets(widget, children) : nil
            return largestOfChildren(children, orientation, widths: widths, offsets: offsets)
        }
        var total = StackLayout.gaps(widget, children, stack).reduce(0, +)
        for (index, child) in children.enumerated() {
            guard let size = largestSize(child, orientation, forSize: widths?[index] ?? -1) else { return nil }
            total += size
        }
        return total
    }

    /// The largest of `children`'s largest sizes, each for its width in `widths` and from its
    /// offset in `offsets` when given.
    private static func largestOfChildren(_ children: [WidgetPointer], _ orientation: GtkOrientation,
                                          widths: [Int]?, offsets: [Int]? = nil) -> Int? {
        var largest = 0
        for (index, child) in children.enumerated() {
            guard let size = largestSize(child, orientation, forSize: widths?[index] ?? -1) else { return nil }
            largest = max(largest, (offsets?[index] ?? 0) + size)
        }
        return largest
    }
}
