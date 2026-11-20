// Sources/Elements/Grid+WinUI.swift
/*
 Grid on WinUI: its rows' cells laid out by GridLayout, in rows and columns as SwiftUI's Grid lays them
 out (and the Linux renderer). Rows inserted or removed at run time are reconciled like any container's
 children (RenderNode.syncChildren over the cells in reading order).

 Not yet: a Group in a row, whose children SwiftUI makes separate columns; a Spacer's minimum, which
 SwiftUI does not set aside in a Grid (it overflows by it; on Linux the other lines make room for
 it; here a Spacer cell has none, its empty panel asking for nothing); a ScrollView in a cell (measured
 at its whole content, it does not scroll; the stacks let it shrink).
*/

import CWinUI

extension Grid: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try GridLayout()
        node.state = layout
        return layout.panel.object
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? GridLayout else { return }
        let props = Props(node.properties)
        let alignment = alignments(props.alignment)
        if layout.horizontal != alignment.horizontal || layout.vertical != alignment.vertical
            || layout.horizontalSpacing != props.horizontalSpacing || layout.verticalSpacing != props.verticalSpacing {
            layout.horizontal = alignment.horizontal
            layout.vertical = alignment.vertical
            layout.horizontalSpacing = props.horizontalSpacing
            layout.verticalSpacing = props.verticalSpacing
            layout.invalidate()
        }
        let rows = node.effectiveElement.subviews?["rows"] as? [[any ActionUIElementBase]] ?? []
        let nodes = node.syncChildren(rows.flatMap { $0 })
        var cells: [[GridLayout.Cell]] = []
        var start = 0
        for row in rows {
            let end = min(start + row.count, nodes.count)
            // One that takes no place (an EmptyView, a Link with no URL) takes no cell.
            cells.append(nodes[start..<end].compactMap { child in
                guard !child.takesNoPlace, let view = child.outerView else { return nil }
                return GridLayout.Cell(view: view, expansion: child.expansion, cap: child.caps, isSpacer: child.element.type == "Spacer")
            })
            start = end
        }
        layout.setRows(cells.filter { !$0.isEmpty })
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
