// Sources/Layout/FormLayout.swift
/*
 The label column of a Form, as macOS lays out a Form (measured on macOS 27, the layout parity
 fixtures): the titles of its LabeledContent rows end at a column as wide as the widest title, the
 content of every row starts 8 points after it (the LabeledContent row's own spacing), and a row
 without a title starts there too. With no titled row there is no column, and the rows start at
 the Form's leading edge. An empty title makes a column of 0, so the content starts at 8.

 The column takes a title's trailing edge as its row lays the title out at the row's natural
 width, not the title's width alone (measured): a row's leading padding, or a frame wider than the
 row's content, which is centered in it, moves the title and the column with it, and a Group's or
 Section's padding does the same to the rows it goes on.

 The Form is a VStack (StackLayout) that moves each row by its offset here: a LabeledContent row
 by the column less its title's trailing edge, any other row by the column plus 8. A Section's or
 Group's rows are the Form's own (stackChildren), so their titles line up with the Form's.
*/

import CAdwaita

/// Attached to a Form's widget.
@MainActor
final class FormConfiguration {}

let formConfigurationKey = "actionui-form"

/// Attached to a LabeledContent's widget, whose first child is its title.
@MainActor
final class LabeledRowMarker {}

let labeledRowMarkerKey = "actionui-labeled-row"

@MainActor
enum FormLayout {
    /// The leading offset of each of `children` (a stack's children as it lays them out) when
    /// `widget` is a Form; nil when it is not.
    static func offsets(_ widget: WidgetPointer, _ children: [WidgetPointer]) -> [Int]? {
        guard attached(FormConfiguration.self, on: widget, key: formConfigurationKey) != nil else { return nil }
        let titles = children.map(titleEnd)
        guard let column = titles.compactMap({ $0 }).max() else {
            return Array(repeating: 0, count: children.count)
        }
        let gap = StackSolver.length(StackLayout.defaultSpacing)
        return titles.map { title in title.map { column - $0 } ?? column + gap }
    }

    /// The trailing edge of a row's title in the row, at the row's natural width, when the row
    /// holds a LabeledContent (inside its box, and inside a Group's or Section's child box); nil
    /// for any other row.
    private static func titleEnd(_ row: WidgetPointer) -> Int? {
        var widget = row
        var start = 0
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(row, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        var width = Int(natural)
        while attached(BoxLayout.self, on: widget, key: boxLayoutKey) != nil {
            guard let content = ModifierBox.content(of: widget), let inner = gtk_widget_get_first_child(content) else { return nil }
            let placement = ModifierBox.elementPlacement(inBox: widget, width: width)
            start += placement.start
            width = placement.width
            widget = inner
        }
        guard attached(LabeledRowMarker.self, on: widget, key: labeledRowMarkerKey) != nil,
              let stack = attached(StackConfiguration.self, on: widget, key: stackConfigurationKey) else { return nil }
        // The row is an HStack of the title and the content, centered in a row wider than they are.
        let children = stackChildren(widget)
        let widths = StackLayout.childWidths(widget, children, width: width)
        guard let title = widths.first else { return nil }
        let length = StackSolver.length(of: widths, gaps: StackLayout.gaps(children, stack))
        return start + StackSolver.centeredStart(length: length, available: width) + title
    }
}
