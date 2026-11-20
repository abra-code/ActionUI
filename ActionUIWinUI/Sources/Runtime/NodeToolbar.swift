// Sources/Runtime/NodeToolbar.swift
/*
 The toolbar a view declares ("toolbar": ToolbarItem and ToolbarItemGroup elements) on WinUI, shown in
 its window's command bar (WindowCommandBar), as SwiftUI on macOS shows a view's toolbar items in the
 window's toolbar and as the Linux renderer shows them in the screen's header bar (NodeToolbar.swift
 there). A ToolbarItem shows its content, a ToolbarItemGroup each of its children, at the item's
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
 persistent toolbar (ToolbarHelper.screenToolbarItems leaves it out).

 Not yet: the toolbars of views inside a NavigationStack (the stack's header row); persistentToolbar;
 searchable; a toolbar inserted at run time into a window whose document had none (logged once).
*/

@MainActor
final class NodeToolbar {
    private weak var node: RenderNode?
    /// The ToolbarItem and ToolbarItemGroup elements shown.
    private let items: [any ActionUIElementBase]
    /// The content nodes, by element id.
    private var itemNodes: [Int: RenderNode] = [:]
    private weak var bar: WindowCommandBar?
    private static var reportedInNavigation = false
    private static var reportedWithoutBar = false

    /// A node's toolbar, or nil when its element declares none. Called while the node is made, which
    /// may be in its parent's sync: it reads nothing from the model.
    static func make(for node: RenderNode) -> NodeToolbar? {
        let items = ToolbarHelper.screenToolbarItems(of: node.element)
        return items.isEmpty ? nil : NodeToolbar(node, items: items)
    }

    private init(_ node: RenderNode, items: [any ActionUIElementBase]) {
        self.node = node
        self.items = items
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

    /// Whether `node` is inside a navigation container, whose screens' toolbars belong to its header.
    private static func inNavigation(_ node: RenderNode) -> Bool {
        var current = node.parent
        while let candidate = current {
            if ToolbarHelper.isNavigationContainer(candidate.element.type) { return true }
            current = candidate.parent
        }
        return false
    }

    /// Makes the content nodes of the items and shows them in the window's command bar. Runs in the
    /// node's sync: the placements it reads mark the node dirty, and new content nodes sync after it.
    func update() {
        guard let node else { return }
        guard !Self.inNavigation(node) else {
            if !Self.reportedInNavigation {
                Self.reportedInNavigation = true
                ActionUIModel.shared.logger.log("Toolbar: the toolbar of a view inside a NavigationStack is not shown on Windows yet", .warning)
            }
            return
        }
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
        let bar = WindowCommandBar.of(windowUUID: node.windowModel.windowUUID)
        if bar !== self.bar {
            self.bar?.remove(owner: ObjectIdentifier(self))
            self.bar = bar
        }
        bar?.set(owner: ObjectIdentifier(self), items: shown)
        // The window makes its bar when its document is loaded: a toolbar inserted later into a document
        // that had none has no bar to show in.
        if bar == nil, !shown.isEmpty, !Self.reportedWithoutBar {
            Self.reportedWithoutBar = true
            ActionUIModel.shared.logger.log("Toolbar: a toolbar added after the window was made is not shown on Windows yet", .warning)
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
