// Sources/Runtime/NodeToolbar.swift
/*
 The toolbar a view declares ("toolbar": ToolbarItem and ToolbarItemGroup elements), shown in its
 screen's header bar (ScreenBar, the nearest one above the view), as SwiftUI shows a view's
 toolbar items in its navigation bar. A ToolbarItem shows its content, a ToolbarItemGroup each of
 its children, at the item's placement:

 - leading (the start of the bar): topBarLeading, cancellationAction, navigation;
 - principal (in place of the title): principal;
 - trailing (the end of the bar): everything else, as the web renderer places them: automatic,
   topBarTrailing, primaryAction, confirmationAction, destructiveAction, status, and for now
   secondaryAction and bottomBar;
 - keyboard: not shown (no software keyboard).

 The contents are nodes of the view's (made like its children, not among them), so they inherit
 its environment. A navigation container's own toolbar is its persistent toolbar
 (ToolbarHelper.screenToolbarItems), not shown yet. A view with no screen above it (a popover)
 shows no toolbar.
*/

import CAdwaita

@MainActor
final class NodeToolbar {
    private weak var node: RenderNode?
    /// The content nodes, by element id.
    private var itemNodes: [Int: RenderNode] = [:]
    private weak var bar: ScreenBar?

    private final class WeakToolbar {
        weak var toolbar: NodeToolbar?
        init(_ toolbar: NodeToolbar) { self.toolbar = toolbar }
    }

    /// Every toolbar alive, so a screen bar attached after the first sync reaches the toolbars
    /// below it, also those below template rows and toolbar items, which are not child nodes.
    private static var live: [ObjectIdentifier: WeakToolbar] = [:]

    /// A node's toolbar, or nil when its element declares none.
    static func make(for node: RenderNode) -> NodeToolbar? {
        ToolbarHelper.screenToolbarItems(of: node.element).isEmpty ? nil : NodeToolbar(node)
    }

    private init(_ node: RenderNode) {
        self.node = node
        Self.live[ObjectIdentifier(self)] = WeakToolbar(self)
    }

    isolated deinit {
        Self.live[ObjectIdentifier(self)] = nil
    }

    /// The attached nodes at or below `ancestor` that declare a toolbar.
    static func nodes(below ancestor: RenderNode) -> [RenderNode] {
        live.values.compactMap { $0.toolbar?.node }.filter { $0.isAttached && $0.isDescendant(of: ancestor) }
    }

    /// The bar slot of a placement name, nil for one not shown.
    static func slot(_ placement: String) -> ScreenBar.Slot? {
        switch ToolbarItem.Props.Placement(rawValue: placement) ?? .automatic {
        case .topBarLeading, .cancellationAction, .navigation: return .leading
        case .principal: return .principal
        case .keyboard: return nil
        case .automatic, .topBarTrailing, .primaryAction, .confirmationAction, .destructiveAction,
             .status, .secondaryAction, .bottomBar: return .trailing
        }
    }

    /// Makes the content nodes of the items the element declares and shows them in the bar. Runs in
    /// the node's sync: the item placements it reads mark the node dirty, and the new content nodes
    /// sync after it, as new children do.
    func update() {
        guard let node else { return }
        var items: [(slot: ScreenBar.Slot, widget: WidgetPointer)] = []
        var kept: [Int: RenderNode] = [:]
        for item in ToolbarHelper.screenToolbarItems(of: node.element) {
            let placement = ToolbarHelper.placementName(current: node.windowModel.viewModels[item.id]?.properties,
                                                        element: item.properties)
            guard let slot = Self.slot(placement) else { continue }
            let contents: [any ActionUIElementBase]
            if item.type == "ToolbarItemGroup" {
                contents = item.subviews?["children"] as? [any ActionUIElementBase] ?? []
            } else {
                contents = (item.subviews?["content"] as? any ActionUIElementBase).map { [$0] } ?? []
            }
            for content in contents where kept[content.id] == nil {
                let contentNode = itemNodes[content.id] ?? node.auxiliaryNode(for: content)
                kept[content.id] = contentNode
                items.append((slot, contentNode.outerWidget))
            }
        }
        let gone = itemNodes.filter { kept[$0.key] == nil }
        itemNodes = kept
        let bar = node.nearestScreenBar
        if bar !== self.bar {
            self.bar?.remove(owner: self)
            self.bar = bar
        }
        bar?.set(owner: self, items: items)
        // After the bar let their boxes go.
        for node in gone.values {
            if gtk_widget_get_parent(node.outerWidget) != nil {
                gtk_widget_unparent(node.outerWidget)
            }
            node.detach()
        }
    }

    /// The content nodes: they inherit the node's environment, as its children do.
    var nodes: [RenderNode] {
        Array(itemNodes.values)
    }

    /// The content node whose box is `widget`.
    func itemNode(showing widget: WidgetPointer) -> RenderNode? {
        itemNodes.values.first { $0.outerWidget == widget }
    }

    /// The node left the tree: its items leave the bar.
    func detach() {
        bar?.remove(owner: self)
        bar = nil
        for node in itemNodes.values {
            node.detach()
        }
        itemNodes = [:]
    }
}
