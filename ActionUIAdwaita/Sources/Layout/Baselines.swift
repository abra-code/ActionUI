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
 it gets beyond what it asked for, as GTK centers its text then (by none or all of it when it is
 aligned to its top or bottom).

 Only the first baseline: GTK reports one per widget, so a stack aligned on lastTextBaseline uses it
 too, which differs from SwiftUI only for text of more than one line.

 A control built from a horizontal GtkBox (a Picker's title and dropdown, a Stepper, a TextField's
 title and entry in a Form) gives the topmost of its shown parts' baselines, each at the box's
 height, as the box lays them out; GTK's own baseline for such a box is its title's at the title's
 height, which is not where the box draws it. A control whose GTK widget reports no baseline but
 shows a line of text, or lines up as if it did, carries a TextLineMarker (measured on macOS 27: a
 Picker's title sits on its pop-up's text, a Slider's beside its middle, a TextEditor's near its
 top).

 Containers with layouts of their own (GroupBox, List) report no baseline yet, so they line up by
 their bottom where SwiftUI uses their first text.
*/

import CAdwaita

/// Attached to a control's widget that reports no baseline to GTK though it shows a line of text,
/// or lines up as if it did: where the line is (Baselines).
@MainActor
final class TextLineMarker {
    enum Place {
        /// A line of the widget's font centered in it (a dropdown's, a slider's).
        case centered
        /// A line `inset` below the widget's top (a text view's first line).
        case top(inset: Int)
    }

    let place: Place

    init(_ place: Place) {
        self.place = place
    }
}

let textLineMarkerKey = "actionui-text-line"

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
        } else if let marker = attached(TextLineMarker.self, on: widget, key: textLineMarkerKey) {
            let line = fontLine(widget)
            switch marker.place {
            case .centered: return (height - line.ascent - line.descent) / 2 + line.ascent
            case .top(let inset): return inset + line.ascent
            }
        } else if g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_box_get_type()) != 0,
                  gtk_orientable_get_orientation(OpaquePointer(widget)) == GTK_ORIENTATION_HORIZONTAL {
            // Each part at the box's full height: the controls' parts fill it, are centered in it,
            // or are aligned to its top or bottom (a radio group's title), which the leaf rule
            // below models.
            var baselines: [Int] = []
            var child = gtk_widget_get_first_child(widget)
            while let part = child {
                if gtk_widget_get_visible(part) != 0 {
                    var minimum: Int32 = 0
                    var natural: Int32 = 0
                    gtk_widget_measure(part, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
                    if let baseline = first(part, width: Int(natural), height: height) {
                        baselines.append(baseline)
                    }
                }
                child = gtk_widget_get_next_sibling(part)
            }
            return baselines.min()
        } else {
            var minimum: Int32 = 0
            var natural: Int32 = 0
            var minimumBaseline: Int32 = -1
            var naturalBaseline: Int32 = -1
            gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, Int32(clamping: width), &minimum, &natural,
                               &minimumBaseline, &naturalBaseline)
            guard naturalBaseline >= 0 else { return nil }
            // Given more height than it asked for, a widget aligned to its top keeps its baseline; one
            // aligned to its bottom moves down by all of it; a filling or centered one by half, as GTK
            // centers its text.
            let extra = max(height - Int(natural), 0)
            switch gtk_widget_get_valign(widget) {
            case GTK_ALIGN_START: return Int(naturalBaseline)
            case GTK_ALIGN_END: return Int(naturalBaseline) + extra
            default: return Int(naturalBaseline) + extra / 2
            }
        }
        return zip(children, places).compactMap { child, place in
            first(child, width: place.width, height: place.height).map { place.y + $0 }
        }.min()
    }

    /// The ascent and descent of a line of `widget`'s font, in pixels.
    private static func fontLine(_ widget: WidgetPointer) -> (ascent: Int, descent: Int) {
        guard let context = gtk_widget_get_pango_context(widget), let metrics = pango_context_get_metrics(context, nil, nil) else {
            return (0, 0)
        }
        defer { pango_font_metrics_unref(metrics) }
        // Pango units: 1024 to a pixel (PANGO_SCALE), rounded up as a GtkLabel reports its baseline
        // and height (measured: a layout baseline of 14.42 px and height 17.6 report 15 and 18), so
        // a title label's text lands on the line: rounding to nearest put it 1 pixel above.
        let pixels = { (units: Int) in (units + 1023) / 1024 }
        let ascent = Int(pango_font_metrics_get_ascent(metrics))
        let descent = Int(pango_font_metrics_get_descent(metrics))
        return (pixels(ascent), pixels(ascent + descent) - pixels(ascent))
    }
}
