// Sources/Runtime/TemplateRows.swift
/*
 The template form of a container (VStack, HStack, LazyVStack, LazyHStack, ZStack, GroupBox,
 Section), as on Apple and Linux: one instance of the "template" element per content row
 (states["content"], set by setElementRows or appendElementRows), the template shown with the row's
 data ($1 is its first column; RenderNode.templateRowNode). A row shown with the same data at the
 same place keeps its instance (its objects' state, its text's selection); a row whose data or place
 changes gets a new one, as on Linux (TemplateRows.swift there) and in a List's template form.

 Every instance is made when its row arrives (eager), as on Linux: a lazy stack makes all its rows at
 once too.
*/

/// A container's template instances, in row order.
@MainActor
final class TemplateRows {
    /// Each row's instance, in row order.
    private(set) var nodes: [RenderNode] = []

    /// The container types that take a template, as Core's specs do.
    static let containerTypes: Set<String> = ["VStack", "HStack", "LazyVStack", "LazyHStack", "ZStack", "GroupBox", "Section"]

    /// What `node` shows: with a template (on a container that takes one), one instance per content
    /// row, and no children; else its children, and no instances. In order.
    func contentNodes(of node: RenderNode) -> [RenderNode] {
        guard Self.containerTypes.contains(node.element.type),
              let template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase else {
            removeAll(from: node)
            return node.syncChildren(node.subviews("children"))
        }
        _ = node.syncChildren([])
        sync(node, template: template, rows: node.model.states["content"] as? [[String]] ?? [])
        return nodes
    }

    /// Makes `nodes` show `rows`: an instance whose row is unchanged at its index is kept; the others
    /// are made again, and those past the last row released.
    private func sync(_ container: RenderNode, template: any ActionUIElementBase, rows: [[String]]) {
        for (index, row) in rows.enumerated() {
            if index < nodes.count, nodes[index].model.templateContext?.row == row { continue }
            let node = container.templateRowNode(template, row: row, rowIndex: index)
            if index < nodes.count {
                container.releaseTemplateNode(nodes[index])
                nodes[index] = node
            } else {
                nodes.append(node)
            }
        }
        while nodes.count > rows.count {
            container.releaseTemplateNode(nodes.removeLast())
        }
    }

    /// Releases every instance (the container shows its children again).
    private func removeAll(from container: RenderNode) {
        for node in nodes {
            container.releaseTemplateNode(node)
        }
        nodes = []
    }
}
