// Sources/Layout/FormLayout.swift
/*
 The label column of a Form, as macOS lays out a Form (measured on macOS 27, the layout parity
 fixtures): the titles of its LabeledContent, Picker, Stepper, ColorPicker, switch Toggle, TextField
 and SecureField rows end at a column as wide as the widest title, the content of every row starts
 8 points after it (the row's own spacing), and a row without a title starts there too. With no
 titled row there is no column, and the rows start at the Form's leading edge. An empty title makes
 a column of 0, so the content starts at 8. A control whose title labelsHidden hides is a row
 without a title, and a checkbox Toggle's title stays beside its checkbox in the content column
 (measured).

 The column takes a title's trailing edge as its row lays the title out at the row's natural
 width, not the title's width alone (measured): a row's leading padding, or a frame wider than the
 row's content, which is centered in it, moves the title and the column with it, and a Group's or
 Section's padding does the same to the rows it goes on.

 A row that is a stack takes its label from the titled controls inside it (measured): a TextField
 after a 30-point Color in an HStack row ends its title, and so the column, at 30 + 8 + its title;
 several titles in one row make the average of where they end, stack by stack (labelEnd).

 The Form is a VStack (StackLayout) that moves each row by its offset here: a row with a label by
 the column less where its label ends, any other row by the column plus 8. A Section's or
 Group's rows are the Form's own (stackChildren), so their titles line up with the Form's.
*/

import CAdwaita

/// Attached to a Form's widget.
@MainActor
final class FormConfiguration {}

let formConfigurationKey = "actionui-form"

/// Attached to the widget of an element that shows its title in a Form's label column.
@MainActor
final class LabeledRowMarker {
    enum Layout {
        /// A LabeledContent: a StackLayout HStack of the title and the content, centered in a
        /// row wider than they are.
        case stack
        /// A control (Picker, Stepper, ColorPicker, switch Toggle, a text field in a Form): a
        /// GtkBox whose first child is the title, packed at its start; a hidden title
        /// (labelsHidden) is no title.
        case box
    }

    let layout: Layout

    init(_ layout: Layout) {
        self.layout = layout
    }
}

let labeledRowMarkerKey = "actionui-labeled-row"

@MainActor
enum FormLayout {
    /// The leading offset of each of `children` (a stack's children as it lays them out) when
    /// `widget` is a Form; nil when it is not.
    static func offsets(_ widget: WidgetPointer, _ children: [WidgetPointer]) -> [Int]? {
        guard attached(FormConfiguration.self, on: widget, key: formConfigurationKey) != nil else { return nil }
        let titles = children.map(labelEnd)
        guard let column = titles.compactMap({ $0 }).max() else {
            return Array(repeating: 0, count: children.count)
        }
        let gap = StackSolver.length(StackLayout.defaultSpacing)
        return titles.map { title in title.map { column - $0 } ?? column + gap }
    }

    /// Where a row's label ends in the row, at the row's natural width (labelEnd(_:width:)),
    /// rounded; nil when nothing in the row has a title. It can be negative (a negative leading
    /// padding on a short title; measured: the column is then negative too, and the other rows'
    /// content starts 8 after it), so it is not a StackSolver length.
    private static func labelEnd(_ row: WidgetPointer) -> Int? {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(row, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        return labelEnd(row, width: Int(natural)).map { Int($0.rounded(.toNearestOrAwayFromZero)) }
    }

    /// Where the label of `widget` laid out `width` wide ends, from its leading edge, as SwiftUI
    /// combines the alignment a Form lines its labels up on (measured on macOS 27):
    /// - a LabeledContent's or a control's title: where the title ends;
    /// - an HStack, VStack or ZStack: the average of its children's, each where the stack places
    ///   the child (SwiftUI averages an alignment several children give: two titles 64 and 188
    ///   points in make a column of 126);
    /// - through the boxes around them, so padding and frames move it.
    /// nil when nothing in it has a title. A Form inside does not count: it lines up its own rows.
    private static func labelEnd(_ widget: WidgetPointer, width: Int) -> Double? {
        var widget = widget
        var start = 0
        var width = width
        while attached(BoxLayout.self, on: widget, key: boxLayoutKey) != nil {
            guard let content = ModifierBox.content(of: widget), let inner = gtk_widget_get_first_child(content) else { return nil }
            let placement = ModifierBox.elementPlacement(inBox: widget, width: width)
            start += placement.start
            width = placement.width
            widget = inner
        }
        if let marker = attached(LabeledRowMarker.self, on: widget, key: labeledRowMarkerKey) {
            return titleEnd(widget, marker, width: width).map { Double(start + $0) }
        }
        guard attached(FormConfiguration.self, on: widget, key: formConfigurationKey) == nil else { return nil }
        let children: [WidgetPointer]
        let placements: [(x: Int, width: Int)]
        if attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) != nil {
            children = stackChildren(widget)
            placements = StackLayout.horizontalPlacements(widget, children, width: width)
        } else if attached(ZStackConfiguration.self, on: widget, key: zStackConfigurationKey) != nil {
            children = stackChildren(widget)
            placements = ZStackLayout.horizontalPlacements(widget, width: width)
        } else {
            return nil
        }
        let ends = zip(children, placements).compactMap { child, place in
            labelEnd(child, width: place.width).map { Double(place.x) + $0 }
        }
        guard !ends.isEmpty else { return nil }
        return Double(start) + ends.reduce(0, +) / Double(ends.count)
    }

    /// Where the title of a LabeledContent or a control `width` wide ends in it; nil when its
    /// title is hidden.
    private static func titleEnd(_ widget: WidgetPointer, _ marker: LabeledRowMarker, width: Int) -> Int? {
        if marker.layout == .box {
            guard let title = gtk_widget_get_first_child(widget), gtk_widget_get_visible(title) != 0 else { return nil }
            var minimum: Int32 = 0
            var natural: Int32 = 0
            gtk_widget_measure(title, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
            return Int(natural)
        }
        guard let stack = attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) else { return nil }
        // An HStack of the title and the content, centered in a row wider than they are.
        let children = stackChildren(widget)
        let widths = StackLayout.childWidths(widget, children, width: width)
        guard let title = widths.first else { return nil }
        let length = StackSolver.length(of: widths, gaps: StackLayout.gaps(children, stack))
        return StackSolver.centeredStart(length: length, available: width) + title
    }
}
