// Sources/Layout/Baselines.swift
/*
 Where a view's first text baseline is, as SwiftUI finds it when an HStack lines up its children
 on firstTextBaseline (measured on macOS 27, the layout parity fixtures):
 - a text's or a control's own baseline;
 - a view without text has none and lines up by its bottom (Colors 20 and 40 tall align their
   bottoms);
 - a stack's is the topmost of its children's that have one, where the stack places them; a stack
   without text has none, so it lines up by its own bottom (a VStack of Colors 10 and 30 tall
   aligns its bottom, not its first child's);
 - padding and a frame carry the content's baseline with the content, and the bottom of a box
   without text is the box's.

 Found at a given size from the places the layouts give when they allocate
 (StackLayout.placements, ZStackLayout.placements, ModifierBox.contentFrame and elementFrame), so an
 HStack can find its children's baselines before it places them. A GTK widget of its own (a label,
 an entry) gives the baseline GTK measures for it at that width, moved down by half of any height
 it gets beyond what it asked for, as GTK centers its text then.

 Only the first baseline: GTK reports one per widget, so a stack aligned on lastTextBaseline uses it
 too, which differs from SwiftUI only for text of more than one line.

 Containers with layouts of their own (GroupBox, List, a control built from a GtkBox) report no
 baseline yet, so they line up by their bottom where SwiftUI uses their first text.
*/

import CAdwaita

@MainActor
enum Baselines {
    /// The first text baseline of `widget` laid out `width` x `height`, from its top; nil when
    /// nothing in it has text (it lines up by its bottom).
    static func first(_ widget: WidgetPointer, width: Int, height: Int) -> Int? {
        if attached(BoxLayout.self, on: widget, key: boxLayoutKey) != nil {
            guard let content = ModifierBox.content(of: widget), let element = layoutChildren(content).first,
                  !Group.isFlattened(element) else { return nil }
            let frame = ModifierBox.contentFrame(widget, width: width, height: height)
            let place = ModifierBox.elementFrame(content, width: frame.width, height: frame.height)
            return first(element, width: place.width, height: place.height).map { frame.y + place.y + $0 }
        }
        let children: [WidgetPointer]
        let places: [(x: Int, y: Int, width: Int, height: Int)]
        if attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) != nil {
            children = stackChildren(widget)
            places = StackLayout.placements(widget, children, width: width, height: height)
        } else if attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) != nil {
            children = stackChildren(widget)
            places = ZStackLayout.placements(widget, width: width, height: height)
        } else {
            var minimum: Int32 = 0
            var natural: Int32 = 0
            var minimumBaseline: Int32 = -1
            var naturalBaseline: Int32 = -1
            gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, Int32(clamping: width), &minimum, &natural,
                               &minimumBaseline, &naturalBaseline)
            guard naturalBaseline >= 0 else { return nil }
            return Int(naturalBaseline) + max(height - Int(natural), 0) / 2
        }
        return zip(children, places).compactMap { child, place in
            first(child, width: place.width, height: place.height).map { place.y + $0 }
        }.min()
    }
}
