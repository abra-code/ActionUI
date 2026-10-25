// Sources/Runtime/RenderNode.swift
/*
 One element instance in a window's render tree: the element, its view model, its renderer, the
 widget the renderer made, and the ModifierBox around it, which applies the base modifiers and is
 what the parent lays out.

 Syncing a node runs its renderer's update inside UpdateGuard (so the signals GTK emits for the
 renderer's own widget changes reach no action) and inside withObservationTracking (so a change to
 anything the update read marks the node dirty, and SyncScheduler syncs it again). The sheet,
 full-screen cover and popover an element declares (NodePresentations) follow its view model's
 visibility states, read in the same sync. Its toolbar (NodeToolbar) shows in the header bar of its
 screen (ScreenBar).

 Ownership: a node keeps a reference on its widget and its box, so they live as long as the node even
 when GTK drops its own (a closed window); a parent keeps its child nodes; the window keeps the
 root. Closures handed to GTK capture nodes weakly. A node that leaves the tree is detached: its
 widget is unparented and a pending sync of it is skipped.
*/

import CAdwaita
import Observation

@MainActor
final class RenderNode {
    let element: any ActionUIElementBase
    let model: ViewModel
    let windowModel: WindowModel
    private(set) weak var parent: RenderNode?
    /// The number of ancestors: SyncScheduler syncs parents before children.
    let depth: Int
    let renderer: any ActionUIAdwaitaRenderer.Type
    /// The renderer's widget, whose reference the node holds (released with the node, or when the
    /// widget is replaced). Set at the end of init: makeWidget receives the node itself, so a
    /// renderer can connect signals that capture it. Replaced when the renderer's widgetKind
    /// changes.
    var widget: WidgetPointer! { ownedWidget?.widget }
    private var ownedWidget: OwnedObject?
    /// The renderer's widgetKind when `widget` was made: the kind makeWidget makes.
    private(set) var widgetKind = 0
    /// The ModifierBox holding `widget`: what a parent places among its children. The node holds its
    /// reference too.
    var outerWidget: WidgetPointer! { ownedOuterWidget?.widget }
    private var ownedOuterWidget: OwnedObject?
    /// False once the node has left the tree.
    private(set) var isAttached = true
    /// The inherited base modifiers, with what the renderer adds (a Form's inForm; Environment),
    /// computed at the start of each sync.
    private(set) var environment = Environment()
    /// The child nodes, keyed by element id.
    private(set) var childNodes: [Int: RenderNode] = [:]
    /// Child nodes made during this node's sync, synced after it, outside its observation
    /// tracking: what a child reads must mark the child dirty, not its parent.
    private var unsyncedChildren: [RenderNode] = []
    /// The sheet, full-screen cover and popover the element declares; nil when it declares none.
    private(set) var presentations: NodePresentations?
    /// The toolbar the element declares, shown in its screen's header bar; nil when it declares none.
    private(set) var toolbar: NodeToolbar?
    /// The context menu the element declares, opened on a right click; nil when it declares none.
    private(set) var contextMenu: NodeContextMenu?
    /// The background and overlay views the element declares; nil when it declares neither.
    private(set) var decorations: NodeDecorations?
    /// True when NodeAppearance watches the box for the element's onAppearActionID and
    /// onDisappearActionID.
    private var watchesAppearance = false
    /// The persistent toolbar of the navigation container this node is a screen of, set by the
    /// container before the node's first sync (NodeToolbar.persistent(on:items:)).
    var persistentToolbar: NodeToolbar? {
        didSet {
            guard persistentToolbar !== oldValue else { return }
            oldValue?.detach()
            SyncScheduler.shared.markDirty(self)
        }
    }
    /// The header bar of the screen this node is the root of (a page's, a column's, a window's), set
    /// by whoever made the bar. Setting it shows the toolbars of the nodes below in it.
    var screenBar: ScreenBar? {
        didSet { markToolbarsDirty() }
    }
    /// True for the root of a window's document, and for a NavigationStack at the root of a dialog
    /// (set before the first sync): a NavigationStack there takes the window's or the dialog's place
    /// for a header bar.
    var isWindowRoot = false
    /// True for the node whose header bar carries the window's primary menu (AppCommands) because
    /// the window shows none of its own: a NavigationStack or NavigationSplitView that is a window's
    /// document, and from a split view the column carrying the menu when that is a
    /// NavigationStack. The application sets it on a window's document after the first sync, so a
    /// change syncs the node again.
    var showsPrimaryMenu = false {
        didSet {
            if showsPrimaryMenu != oldValue {
                SyncScheduler.shared.markDirty(self)
            }
        }
    }

    var windowUUID: String { windowModel.windowUUID }

    /// The element's current properties: its view model's store once seeded. A tracked read.
    var properties: [String: Any] {
        ActionUIRegistry.shared.currentProperties(element: element, model: model)
    }

    /// The element with the subviews inserted or removed at run time merged in. A tracked read.
    var effectiveElement: any ActionUIElementBase {
        ActionUIRegistry.shared.applyDynamicSubviews(to: element, model: model)
    }

    /// The elements in one of the effective element's subview lists ("children", "rows"). A
    /// tracked read.
    func subviews(_ key: String) -> [any ActionUIElementBase] {
        effectiveElement.subviews?[key] as? [any ActionUIElementBase] ?? []
    }

    /// Makes the node and its widget; the caller syncs it (sync) once it is placed.
    init(element: any ActionUIElementBase, model: ViewModel, windowModel: WindowModel, parent: RenderNode?) {
        self.element = element
        self.model = model
        self.windowModel = windowModel
        self.parent = parent
        self.depth = parent.map { $0.depth + 1 } ?? 0
        self.renderer = ActionUIRegistry.shared.adwaitaRenderer(forElementType: element.type)
        // As sync computes it, so a widget kind that depends on the environment (a TextField in a
        // Form) is made right the first time; sync recomputes it under observation. Untracked: a
        // child is made during its parent's sync, whose observation would take these reads as the
        // parent's.
        UntrackedReads.perform {
            let modifiers = BaseModifiers(ActionUIRegistry.shared.currentProperties(element: element, model: model))
            self.environment = renderer.environment((parent?.environment ?? Environment()).applying(modifiers))
            self.widgetKind = renderer.widgetKind(self)
        }
        let widget = renderer.makeWidget(self)
        // GTK's floating references become the node's own.
        ownedWidget = OwnedObject(retaining: widget)
        ownedOuterWidget = OwnedObject(retaining: ModifierBox.wrap(widget))
        // Before the pointer's handlers, which cover the overlay view too (NodeDecorations.pointerAreas).
        decorations = NodeDecorations.make(for: self)
        presentations = NodePresentations.make(for: self)
        toolbar = NodeToolbar.make(for: self)
        contextMenu = NodeContextMenu.make(for: self)
        watchesAppearance = NodeAppearance.watch(self)
        NodeHover.watch(self)
        NodeDrop.watch(self)
    }

    isolated deinit {
        // Released here, on the main actor (GTK's thread), the box before the widget it holds.
        ownedOuterWidget = nil
        ownedWidget = nil
    }

    // MARK: Syncing

    /// Makes the widget show the model, and watches what that read.
    func sync() {
        guard isAttached else { return }
        let previousEnvironment = environment
        var requestedPresentations: Set<NodePresentations.Kind> = []
        UpdateGuard.applying {
            withObservationTracking {
                requestedPresentations = presentations?.requested() ?? []
                let modifiers = BaseModifiers(properties)
                environment = renderer.environment((parent?.environment ?? Environment()).applying(modifiers))
                let kind = renderer.widgetKind(self)
                if kind != widgetKind {
                    replaceWidget(kind: kind)
                }
                renderer.update(widget, self)
                toolbar?.update()
                contextMenu?.update()
                persistentToolbar?.update()
                decorations?.update(modifiers)
                ModifierBox.update(outerWidget, self, renderer.boxModifiers(modifiers))
            } onChange: { [weak self] in
                // The model is main-actor isolated, so changes, and this call, happen on the
                // main thread, before the new value is stored.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    SyncScheduler.shared.markDirty(self)
                }
            }
        }
        let created = unsyncedChildren
        unsyncedChildren = []
        // A changed environment reaches the existing children (new ones compute theirs below).
        // A set: a linear search per child is quadratic in a wide container's first sync.
        if environment != previousEnvironment {
            let new = Set(created.map(ObjectIdentifier.init))
            for child in Array(childNodes.values) + (toolbar?.nodes ?? []) + (persistentToolbar?.nodes ?? []) + (decorations?.nodes ?? [])
            where !new.contains(ObjectIdentifier(child)) {
                SyncScheduler.shared.markDirty(child)
            }
        }
        for child in created {
            child.sync()
        }
        // After the children, outside the observation: the presentations' trees track their own reads.
        presentations?.apply(requestedPresentations)
    }

    /// Puts a new widget of `kind` from the renderer in the box, in place of the current one. The
    /// update that follows makes it show the model, and ModifierBox's update, which compares with
    /// the widget itself, applies the base modifiers to it. Child boxes in the old widget are taken
    /// out; the update puts them in the new one.
    private func replaceWidget(kind: Int) {
        widgetKind = kind
        // Made while `widget` is still the old one, as before the node owned it through OwnedObject.
        let new = renderer.makeWidget(self)
        // The old widget's reference, released when this returns (at the end of the scope, not at
        // its last use), after the widget left its box.
        guard let old = ownedWidget.take() else { return }
        // Set before the new widget is placed, so signals its mapping emits see it.
        ownedWidget = OwnedObject(retaining: new)
        for child in childNodes.values where gtk_widget_is_ancestor(child.outerWidget, old.widget) != 0 {
            gtk_widget_unparent(child.outerWidget)
        }
        if let content = ModifierBox.content(of: outerWidget) {
            gtk_widget_unparent(old.widget)
            gtk_widget_set_parent(new, content)
        }
    }

    // MARK: Children

    /// The child node for `element`: the existing one with its id, or a new one with the element's
    /// view model, synced right after this node's sync. Containers reconcile their children through
    /// syncChildren, also a container of one child, so a child that leaves is taken out.
    func childNode(for element: any ActionUIElementBase) -> RenderNode {
        if let existing = childNodes[element.id] {
            return existing
        }
        let child = RenderNode(element: element, model: childModel(for: element), windowModel: windowModel, parent: self)
        childNodes[element.id] = child
        unsyncedChildren.append(child)
        return child
    }

    /// A node for `element`, with a view model as a child's, that is not one of the child nodes: a
    /// toolbar item's content, kept by NodeToolbar. Synced right after this node's sync, like a new
    /// child; its keeper detaches it.
    func auxiliaryNode(for element: any ActionUIElementBase) -> RenderNode {
        let node = RenderNode(element: element, model: childModel(for: element), windowModel: windowModel, parent: self)
        unsyncedChildren.append(node)
        return node
    }

    /// The view model of a node made for `element` below this one: its registered one, or inside a
    /// template row one of its own.
    private func childModel(for element: any ActionUIElementBase) -> ViewModel {
        if let context = model.templateContext {
            // Inside a template row: the child is a blueprint too, shown with the row's data in a view
            // model of its own, as on Apple (TemplateHelper).
            return Self.templateModel(element, context)
        } else if let registered = windowModel.viewModels[element.id] {
            return registered
        }
        ActionUIModel.shared.logger.log("RenderNode: no view model for element \(element.id) (\(element.type)) in window \(windowUUID); rendering it with an empty one", .warning)
        return ViewModel()
    }

    /// A node for one row of a template container: `template` shown with the row's data, in a view
    /// model of its own whose TemplateContext names this node as the parent (the id actions report)
    /// and the row's index and data. Synced right after this node's sync, like a new child. The
    /// container keeps it, not childNodes (every row has the template's ids), and detaches it when
    /// its row goes.
    func templateRowNode(_ template: any ActionUIElementBase, row: [String], rowIndex: Int) -> RenderNode {
        let context = TemplateContext(parentID: element.id, rowIndex: rowIndex, row: row)
        let node = RenderNode(element: template, model: Self.templateModel(template, context), windowModel: windowModel, parent: self)
        unsyncedChildren.append(node)
        return node
    }

    /// A template instance's view model: the element's properties with the row's data substituted.
    private static func templateModel(_ element: any ActionUIElementBase, _ context: TemplateContext) -> ViewModel {
        let model = ViewModel()
        model.templateContext = context
        model.seedProperties(TemplateHelper.instanceProperties(of: element, row: context.row, logger: ActionUIModel.shared.logger))
        return model
    }

    /// Reconciles the child nodes with `elements`, keyed by element id, in order. `insert` places a
    /// child's widget at an index among the container's children (also for a child already
    /// there, which may have moved); `remove` takes a removed child's widget out. Removed nodes are
    /// detached and dropped.
    func syncChildren(_ elements: [any ActionUIElementBase],
                      insert: (RenderNode, Int) -> Void,
                      remove: (RenderNode) -> Void) {
        let kept = Set(elements.map(\.id))
        // A child whose id now has another view model was removed and an element inserted under
        // its id before this sync (one turn): it is replaced, not reused.
        for (id, child) in childNodes where !kept.contains(id) || child.isReplaced {
            remove(child)
            child.detach()
            childNodes[id] = nil
        }
        for (index, element) in elements.enumerated() {
            insert(childNode(for: element), index)
        }
    }

    /// True when the window has another view model for this node's element id.
    private var isReplaced: Bool {
        // A template instance's model is its own; the id may name the blueprint's registered one.
        guard model.templateContext == nil else { return false }
        guard let registered = windowModel.viewModels[element.id] else { return false }
        return registered !== model
    }

    /// Marks this node and its descendants as out of the tree.
    func detach() {
        // Once: a closing window's tree is detached again when it is released.
        if isAttached && watchesAppearance {
            NodeAppearance.left(self)
        }
        isAttached = false
        presentations?.detach()
        toolbar?.detach()
        persistentToolbar?.detach()
        contextMenu?.detach()
        decorations?.detach()
        for child in childNodes.values {
            child.detach()
        }
    }

    /// The screen bar of this node or of the nearest node above it that has one.
    var nearestScreenBar: ScreenBar? {
        var current: RenderNode? = self
        while let node = current {
            if let bar = node.screenBar {
                return bar
            }
            current = node.parent
        }
        return nil
    }

    /// Syncs again the nodes from this one down that declare a toolbar: their screen bar changed.
    /// Also those below template rows and toolbar items, which are not child nodes (NodeToolbar
    /// keeps the list).
    private func markToolbarsDirty() {
        for node in NodeToolbar.nodes(below: self) {
            SyncScheduler.shared.markDirty(node)
        }
    }

    /// Whether `ancestor` is this node or one above it.
    func isDescendant(of ancestor: RenderNode) -> Bool {
        var current: RenderNode? = self
        while let node = current {
            if node === ancestor {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// Takes down the presentations of this node and its descendants, as detach does (no action,
    /// the states stay), the nodes staying in the tree: the host closes the window, which
    /// AdwDialogHost would answer by closing a sheet instead.
    func takeDownPresentations() {
        presentations?.detach()
        for child in childNodes.values {
            child.takeDownPresentations()
        }
    }

    /// Shows again what the states of this node and its descendants ask for, after
    /// takeDownPresentations (a window that did not close after all).
    func restorePresentations() {
        if let presentations {
            presentations.apply(presentations.requested())
        }
        for child in childNodes.values {
            child.restorePresentations()
        }
    }

    // MARK: Actions

    /// Fires `actionID` for this element, unless a renderer update is running (user signals only).
    func fire(_ actionID: String?, viewPartID: Int = 0, context: Any? = nil) {
        guard let actionID, !actionID.isEmpty, !UpdateGuard.isApplying else { return }
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id,
                                           viewPartID: viewPartID, context: context)
    }
}
