// Sources/Runtime/RenderNode.swift
/*
 One element instance on screen: the element, its view model, its renderer and the WinUI object
 the renderer made, and the child nodes of its subviews. As on Linux (where RenderNode also carries
 modifiers, presentations, toolbars and the rest, which come here one by one):

 - sync runs the renderer's update under observation tracking; a change to anything it read marks
   the node dirty, and SyncScheduler syncs it again in its next flush.
 - Children are kept by element id (syncChildren): a child whose element stays keeps its node and
   its WinUI object; a new one gets a new node, synced right after its parent.
*/

import Observation

@MainActor
package final class RenderNode {
    package let element: any ActionUIElementBase
    package let model: ViewModel
    let windowModel: WindowModel
    private(set) weak var parent: RenderNode?
    /// How deep in the tree: 0 for the root. SyncScheduler syncs parents first.
    let depth: Int
    /// The element type's renderer; the placeholder's when the renderer could not make its object.
    private(set) var renderer: any ActionUIWinUIRenderer.Type
    /// The element's WinUI object.
    package private(set) var view: WinUIObject!

    /// What the renderer keeps for this element instance beside its WinUI object (a stack's
    /// StackLayout), as on Linux.
    var state: AnyObject?

    /// False once the node left the tree (its element was removed, or its window went away).
    private(set) var isAttached = true
    private(set) var childNodes: [Int: RenderNode] = [:]
    /// The child nodes in their elements' order, as the last syncChildren left them.
    package private(set) var orderedChildren: [RenderNode] = []
    /// Children made since the last sync, synced at the end of it.
    private var unsyncedChildren: [RenderNode] = []

    /// The element's current properties: its view model's store once seeded. A tracked read.
    package var properties: [String: Any] {
        ActionUIRegistry.shared.currentProperties(element: element, model: model)
    }

    /// The element with the subviews inserted or removed at run time merged in. A tracked read.
    var effectiveElement: any ActionUIElementBase {
        ActionUIRegistry.shared.applyDynamicSubviews(to: element, model: model)
    }

    func subviews(_ key: String) -> [any ActionUIElementBase] {
        effectiveElement.subviews?[key] as? [any ActionUIElementBase] ?? []
    }

    /// Makes the node and its WinUI object; the caller syncs it once it is placed.
    init(element: any ActionUIElementBase, model: ViewModel, windowModel: WindowModel, parent: RenderNode?) {
        self.element = element
        self.model = model
        self.windowModel = windowModel
        self.parent = parent
        self.depth = parent.map { $0.depth + 1 } ?? 0
        self.renderer = ActionUIRegistry.shared.winUIRenderer(forElementType: element.type)
        do {
            view = try renderer.makeView(self)
        } catch {
            ActionUIModel.shared.logger.log("RenderNode: \(error); showing a placeholder for \(element.type)", .error)
            renderer = PlaceholderRenderer.self
            view = try? renderer.makeView(self)
        }
    }

    // MARK: Syncing

    /// Makes the WinUI object show the model, and watches what that read.
    func sync() {
        guard isAttached, let view else { return }
        withObservationTracking {
            renderer.update(view, self)
        } onChange: { [weak self] in
            // The model is main-actor isolated, so changes, and this call, happen on the main
            // thread, before the new value is stored.
            MainActor.assumeIsolated {
                guard let self else { return }
                SyncScheduler.shared.markDirty(self)
            }
        }
        let created = unsyncedChildren
        unsyncedChildren = []
        for child in created {
            child.sync()
        }
    }

    // MARK: Children

    /// Makes the child nodes match `elements`: those gone leave the tree, new ones are made (and
    /// synced at the end of this node's sync). Returns the nodes in the elements' order.
    func syncChildren(_ elements: [any ActionUIElementBase]) -> [RenderNode] {
        let kept = Set(elements.map(\.id))
        // A child whose id now has another view model was removed and an element inserted under
        // its id before this sync: it is replaced, not reused.
        for (id, child) in childNodes where !kept.contains(id) || child.isReplaced {
            child.detach()
            childNodes[id] = nil
        }
        orderedChildren = elements.map(childNode(for:))
        return orderedChildren
    }

    private func childNode(for element: any ActionUIElementBase) -> RenderNode {
        if let existing = childNodes[element.id] {
            return existing
        }
        let child = RenderNode(element: element, model: childModel(for: element), windowModel: windowModel, parent: self)
        childNodes[element.id] = child
        unsyncedChildren.append(child)
        return child
    }

    private func childModel(for element: any ActionUIElementBase) -> ViewModel {
        if let registered = windowModel.viewModels[element.id] {
            return registered
        }
        ActionUIModel.shared.logger.log("RenderNode: no view model for element \(element.id) (\(element.type)) in window \(windowModel.windowUUID); rendering it with an empty one", .warning)
        return ViewModel()
    }

    /// True when the window has another view model for this node's element id.
    private var isReplaced: Bool {
        guard let registered = windowModel.viewModels[element.id] else { return false }
        return registered !== model
    }

    /// Marks this node and its descendants as out of the tree.
    func detach() {
        isAttached = false
        orderedChildren = []
        for child in childNodes.values {
            child.detach()
        }
    }
}
