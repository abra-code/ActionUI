// Sources/Elements/Form+Adwaita.swift
/*
 Form on GTK: laid out as macOS lays out a Form (its columns style; measured on macOS 27, the
 layout parity fixtures). It is a VStack of its rows, 8 points apart and aligned to its leading
 edge, as large as its rows unless one of them fills, and centered in its parent like a VStack.
 The titles of its LabeledContent rows end at a label column as wide as the widest title, and every
 row's content starts 8 points after it (FormLayout). A Section's and a Group's rows are the Form's
 own, so a Section adds no space and its header sits in the content column.
*/

import CAdwaita

extension Form: ActionUIAdwaitaRenderer {
    /// The space between two rows, measured on macOS 27.
    static let rowSpacing = 8.0

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = StackLayout.makeStack(axis: .vertical)
        StackLayout.configure(widget, spacing: rowSpacing, alignment: .start)
        attach(FormConfiguration(), to: widget, key: formConfigurationKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        syncContainerChildren(node, widget, node.subviews("children"))
    }
}
