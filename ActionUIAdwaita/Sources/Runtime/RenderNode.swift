// Sources/Runtime/RenderNode.swift
/*
 One element instance in a window's render tree: the element, its view model, its renderer, the
 widget the renderer made, and the ModifierBox around it, which applies the base modifiers and is
 what the parent lays out.

 Syncing a node runs its renderer's update inside UpdateGuard (so the signals GTK emits for the
 renderer's own widget changes reach no action) and inside withObservationTracking (so a change to
 anything the update read marks the node dirty, and SyncScheduler syncs it again).

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
    /// The renderer's widget. Set at the end of init: makeWidget receives the node itself, so a
    /// renderer can connect signals that capture it. Replaced when the renderer's widgetKind
    /// changes.
    private(set) var widget: WidgetPointer!
    /// The renderer's widgetKind when `widget` was made: the kind makeWidget makes.
    private(set) var widgetKind = 0
    /// The ModifierBox holding `widget`: what a parent places among its children.
    private(set) var outerWidget: WidgetPointer!
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
        self.widgetKind = renderer.widgetKind(self)
        let widget = renderer.makeWidget(self)
        // Sinks GTK's floating reference into the node's own.
        g_object_ref_sink(UnsafeMutableRawPointer(widget))
        self.widget = widget
        let box = ModifierBox.wrap(widget)
        g_object_ref_sink(UnsafeMutableRawPointer(box))
        self.outerWidget = box
    }

    isolated deinit {
        if let outerWidget {
            g_object_unref(UnsafeMutableRawPointer(outerWidget))
        }
        if let widget {
            g_object_unref(UnsafeMutableRawPointer(widget))
        }
    }

    // MARK: Syncing

    /// Makes the widget show the model, and watches what that read.
    func sync() {
        guard isAttached else { return }
        let previousEnvironment = environment
        UpdateGuard.applying {
            withObservationTracking {
                let modifiers = BaseModifiers(properties)
                environment = renderer.environment((parent?.environment ?? Environment()).applying(modifiers))
                let kind = renderer.widgetKind(self)
                if kind != widgetKind {
                    replaceWidget(kind: kind)
                }
                renderer.update(widget, self)
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
            for child in childNodes.values where !new.contains(ObjectIdentifier(child)) {
                SyncScheduler.shared.markDirty(child)
            }
        }
        for child in created {
            child.sync()
        }
    }

    /// Puts a new widget of `kind` from the renderer in the box, in place of the current one. The
    /// update that follows makes it show the model, and ModifierBox's update, which compares with
    /// the widget itself, applies the base modifiers to it. Child boxes in the old widget are taken
    /// out; the update puts them in the new one.
    private func replaceWidget(kind: Int) {
        let old: WidgetPointer = widget
        widgetKind = kind
        let new = renderer.makeWidget(self)
        g_object_ref_sink(UnsafeMutableRawPointer(new))
        // Set before the new widget is placed, so signals its mapping emits see it.
        widget = new
        for child in childNodes.values where gtk_widget_is_ancestor(child.outerWidget, old) != 0 {
            gtk_widget_unparent(child.outerWidget)
        }
        if let content = ModifierBox.content(of: outerWidget) {
            gtk_widget_unparent(old)
            gtk_widget_set_parent(new, content)
        }
        g_object_unref(UnsafeMutableRawPointer(old))
    }

    // MARK: Children

    /// The child node for `element`: the existing one with its id, or a new one with the element's
    /// view model, synced right after this node's sync. Containers reconcile their children through
    /// syncChildren, also a container of one child, so a child that leaves is taken out.
    func childNode(for element: any ActionUIElementBase) -> RenderNode {
        if let existing = childNodes[element.id] {
            return existing
        }
        let childModel: ViewModel
        if let registered = windowModel.viewModels[element.id] {
            childModel = registered
        } else {
            ActionUIModel.shared.logger.log("RenderNode: no view model for element \(element.id) (\(element.type)) in window \(windowUUID); rendering it with an empty one", .warning)
            childModel = ViewModel()
        }
        let child = RenderNode(element: element, model: childModel, windowModel: windowModel, parent: self)
        childNodes[element.id] = child
        unsyncedChildren.append(child)
        return child
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
        guard let registered = windowModel.viewModels[element.id] else { return false }
        return registered !== model
    }

    /// Marks this node and its descendants as out of the tree.
    func detach() {
        isAttached = false
        for child in childNodes.values {
            child.detach()
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
