// Sources/Runtime/TemplateRows.swift
/*
 A container's template instances, one per content row, as RenderNode.templateRowNode makes them
 (the template element shown with the row's data, as on Apple): a row shown with the same data at
 the same place keeps its instance and its widgets' state; a row whose data or place changed is
 made again, the old instance detached; rows that went are detached. The instances are not the
 container's child nodes, so a change of the container's environment is passed on to the kept ones
 here. (List keeps its own copy of this logic.)
*/

@MainActor
final class TemplateRows {
    /// Each row's instance, in row order.
    private(set) var nodes: [RenderNode] = []
    /// The container's environment when the rows were last synced.
    private var environment = Environment()

    /// Makes `nodes` show `rows`. `insert` places a new instance's box at its index; `remove` takes
    /// a replaced or gone instance's box out (before it is detached).
    func sync(_ container: RenderNode, template: any ActionUIElementBase, rows: [[String]],
              insert: (RenderNode, Int) -> Void, remove: (RenderNode) -> Void) {
        if container.environment != environment {
            environment = container.environment
            for node in nodes {
                SyncScheduler.shared.markDirty(node)
            }
        }
        for (index, row) in rows.enumerated() {
            if index < nodes.count, nodes[index].model.templateContext?.row == row { continue }
            let node = container.templateRowNode(template, row: row, rowIndex: index)
            if index < nodes.count {
                remove(nodes[index])
                nodes[index].detach()
                nodes[index] = node
            } else {
                nodes.append(node)
            }
            insert(node, index)
        }
        while nodes.count > rows.count {
            let gone = nodes.removeLast()
            remove(gone)
            gone.detach()
        }
    }

    /// Takes every instance out and detaches it.
    func removeAll(remove: (RenderNode) -> Void) {
        for node in nodes {
            remove(node)
            node.detach()
        }
        nodes = []
    }
}
