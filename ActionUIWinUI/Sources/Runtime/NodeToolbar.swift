// Sources/Runtime/NodeToolbar.swift
/*
 The toolbar a view declares ("toolbar": ToolbarItem and ToolbarItemGroup elements) on WinUI, shown in
 its NavigationStack screen's header (the stack's header row, while the screen is on top), else in its
 window's command bar (WindowCommandBar), as SwiftUI shows a view's toolbar items in its navigation
 bar or the window's toolbar and as the Linux renderer shows them in the screen's header bar
 (NodeToolbar.swift there). A ToolbarItem shows its content, a ToolbarItemGroup each of its children, at the item's
 placement:

 - leading: topBarLeading, cancellationAction, navigation;
 - principal (centered): principal;
 - trailing: everything else, as on Linux and the web: automatic, topBarTrailing, primaryAction,
   confirmationAction, destructiveAction, status;
 - overflow (the "see more" button's flyout): secondaryAction;
 - bottom (a row below the content): bottomBar;
 - keyboard: not shown (no software keyboard).

 The contents are auxiliary nodes of the view (RenderNode.auxiliaryNode: made like its children, not
 among them), so they inherit its environment. A navigation container's own toolbar is its
 persistent toolbar (ToolbarHelper.screenToolbarItems leaves it out): the NavigationStack makes it
 (persistent(for:items:)) and shows it on every screen.

 In a NavigationSplitView the items show in their column's header (NavigationSplitView+WinUI.swift).

 Not yet: searchable; a toolbar inserted at run time into a window whose document had none (logged
 once).
*/

@MainActor
final class NodeToolbar {
    private weak var node: RenderNode?
    /// The ToolbarItem and ToolbarItemGroup elements shown.
    private let items: [any ActionUIElementBase]
    /// The content nodes, by element id.
    private var itemNodes: [Int: RenderNode] = [:]
    private weak var bar: (any ToolbarBar)?
    /// The bar the items go to, for the toolbar's node.
    private let barOf: @MainActor (RenderNode) -> (any ToolbarBar)?
    private static var reportedWithoutBar = false

    /// A node's toolbar, or nil when its element declares none. Called while the node is made, which
    /// may be in its parent's sync: it reads nothing from the model.
    static func make(for node: RenderNode) -> NodeToolbar? {
        let items = ToolbarHelper.screenToolbarItems(of: node.element)
        return items.isEmpty ? nil : NodeToolbar(node, items: items, barOf: nearestBar)
    }

    /// A NavigationStack's persistent toolbar (`items`), shown on every screen through the stack's
    /// persistent bar.
    static func persistent(for stack: RenderNode, items: [any ActionUIElementBase]) -> NodeToolbar {
        NodeToolbar(stack, items: items) { stack in
            (stack.state as? NavigationStackState)?.persistentBar(stack: stack)
        }
    }

    /// A navigation container's persistent toolbar (`items`) shown in the bar `bar` gives for it (a
    /// NavigationSplitView's detail column).
    static func persistent(for node: RenderNode, items: [any ActionUIElementBase],
                           bar: @escaping @MainActor (RenderNode) -> (any ToolbarBar)?) -> NodeToolbar {
        NodeToolbar(node, items: items, barOf: bar)
    }

    private init(_ node: RenderNode, items: [any ActionUIElementBase], barOf: @escaping @MainActor (RenderNode) -> (any ToolbarBar)?) {
        self.node = node
        self.items = items
        self.barOf = barOf
    }

    /// The bar of `node`'s screen: the screen's in the NavigationStack it is in (the stack's child it
    /// is under), or its column's in a NavigationSplitView (the split view's child it is under), else
    /// its window's command bar; none in another navigation container.
    private static func nearestBar(_ node: RenderNode) -> (any ToolbarBar)? {
        var screen = node
        var current = node.parent
        while let candidate = current {
            if candidate.element.type == "NavigationStack" {
                return (candidate.state as? NavigationStackState)?.screenBar(for: screen, stack: candidate)
            }
            if candidate.element.type == "NavigationSplitView" {
                return (candidate.state as? NavigationSplitViewState)?.bar(for: screen)
            }
            if ToolbarHelper.isNavigationContainer(candidate.element.type) {
                return nil
            }
            screen = candidate
            current = candidate.parent
        }
        return WindowCommandBar.of(windowUUID: node.windowModel.windowUUID)
    }

    /// The bar slot of a placement name, nil for one not shown.
    static func slot(_ placement: String) -> ToolbarSlot? {
        switch ToolbarItem.Props.Placement(rawValue: placement) ?? .automatic {
        case .topBarLeading, .cancellationAction, .navigation: return .leading
        case .principal: return .principal
        case .keyboard: return nil
        case .secondaryAction: return .overflow
        case .bottomBar: return .bottom
        case .automatic, .topBarTrailing, .primaryAction, .confirmationAction, .destructiveAction, .status: return .trailing
        }
    }

    /// Makes the content nodes of the items and shows them in its bar (its screen's or the window's). Runs in the
    /// node's sync: the placements it reads mark the node dirty, and new content nodes sync after it.
    func update() {
        guard let node else { return }
        var shown: [(slot: ToolbarSlot, view: WinUIObject)] = []
        var kept: [Int: RenderNode] = [:]
        for item in items {
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
                if let view = contentNode.outerView {
                    shown.append((slot, view))
                }
            }
        }
        let gone = itemNodes.filter { kept[$0.key] == nil }
        itemNodes = kept
        let bar = barOf(node)
        if bar !== self.bar {
            self.bar?.remove(owner: ObjectIdentifier(self))
            self.bar = bar
        }
        bar?.set(owner: ObjectIdentifier(self), items: shown)
        // No bar: a toolbar inserted into a window whose document had none (the window makes its bar
        // when the document is loaded).
        if bar == nil, !shown.isEmpty, !Self.reportedWithoutBar {
            Self.reportedWithoutBar = true
            ActionUIModel.shared.logger.log("Toolbar: a toolbar with no bar to show in (added after the window was made) is not shown on Windows yet", .warning)
        }
        // After the bar let their boxes go.
        for gone in gone.values {
            node.releaseAuxiliaryNode(gone)
        }
    }

    /// The node left the tree: its items leave the bar.
    func detach() {
        bar?.remove(owner: ObjectIdentifier(self))
        bar = nil
        itemNodes = [:]
    }
}
