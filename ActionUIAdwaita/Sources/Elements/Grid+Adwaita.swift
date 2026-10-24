// Sources/Elements/Grid+Adwaita.swift
/*
 Grid on GTK: a container laid out by GridLayout, its rows' cells in reading order. Rows inserted
 or removed at run time (insertRow, removeElement) are reconciled like any container's children.

 Not yet: a Group in a row, whose children SwiftUI makes separate columns (here it is one cell
 laid out as a VStack); a Spacer's minimum, which SwiftUI does not set aside in a Grid (it
 overflows by it, centered; here the other lines make room for it).
*/

import CAdwaita

extension Grid: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        GridLayout.makeGrid()
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let configuration = attached(on: widget, key: gridConfigurationKey) else { return }
        let props = Props(node.properties)
        let rows = node.effectiveElement.subviews?["rows"] as? [[any ActionUIElementBase]] ?? []
        let alignment = alignments(props.alignment)
        let horizontalSpacing = props.horizontalSpacing.map { StackSolver.length($0) } ?? GridLayout.defaultSpacing
        let verticalSpacing = props.verticalSpacing.map { StackSolver.length($0) } ?? GridLayout.defaultSpacing
        let horizontalSpacingIsDefault = props.horizontalSpacing == nil
        let verticalSpacingIsDefault = props.verticalSpacing == nil
        let rowLengths = rows.map(\.count)
        if configuration.rowLengths != rowLengths || configuration.horizontal != alignment.horizontal
            || configuration.vertical != alignment.vertical || configuration.horizontalSpacing != horizontalSpacing
            || configuration.verticalSpacing != verticalSpacing
            || configuration.horizontalSpacingIsDefault != horizontalSpacingIsDefault
            || configuration.verticalSpacingIsDefault != verticalSpacingIsDefault {
            configuration.rowLengths = rowLengths
            configuration.horizontal = alignment.horizontal
            configuration.vertical = alignment.vertical
            configuration.horizontalSpacing = horizontalSpacing
            configuration.verticalSpacing = verticalSpacing
            configuration.horizontalSpacingIsDefault = horizontalSpacingIsDefault
            configuration.verticalSpacingIsDefault = verticalSpacingIsDefault
            gtk_widget_queue_resize(widget)
        }
        syncContainerChildren(node, widget, rows.flatMap { $0 })
    }

    static func alignments(_ alignment: Props.Alignment) -> (horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment) {
        switch alignment {
        case .topLeading: return (.start, .start)
        case .top: return (.center, .start)
        case .topTrailing: return (.end, .start)
        case .leading: return (.start, .center)
        case .center: return (.center, .center)
        case .trailing: return (.end, .center)
        case .bottomLeading: return (.start, .end)
        case .bottom: return (.center, .end)
        case .bottomTrailing: return (.end, .end)
        }
    }
}
