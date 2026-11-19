// Sources/Runtime/RenderNode.swift
/*
 One element instance on screen: the element, its view model, its renderer and the WinUI object
 the renderer made, and the child nodes of its subviews. As on Linux (where RenderNode also carries
 modifiers, presentations, toolbars and the rest, which come here one by one):

 - sync runs the renderer's update under observation tracking; a change to anything it read marks
   the node dirty, and SyncScheduler syncs it again in its next flush.
 - Children are kept by element id (syncChildren): a child whose element stays keeps its node and
   its WinUI object; a new one gets a new node, synced right after its parent.
 - The WinUI object sits in a ModifierBox (padding, frame, background, opacity, hidden); a parent lays out the box
   (outerView).
   How the element expands (its renderer's default, overridden per axis by a frame) is known from
   its creation, since a parent lays out a new child before the child's first sync.
*/

import CWinUI
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
    /// The box around it, which applies padding and frame; nil if the shim could not make one.
    private(set) var box: ModifierBox?
    /// What a parent lays out: the box, else the object.
    package var outerView: WinUIObject! { box?.panel.object ?? view }
    /// How the element grows in a stack: the renderer's expansion, overridden per axis by a
    /// frame (one with a maximum expands, a fixed one does not).
    private(set) var expansion: Expansion = []
    /// The axes along which a stack can make the element smaller than it asks for (the renderer's
    /// compression).
    private(set) var compression: Expansion = []
    /// The font and foreground of the element's text: its own modifiers over its parent's
    /// appearance, which descendants inherit (as SwiftUI's environment passes them down).
    private(set) var textAppearance = TextAppearance()
    /// The appearance last applied to the WinUI object (applyTextAppearance), to set it only on a
    /// change.
    private var appliedAppearance: TextAppearance?
    /// Inherited states, as SwiftUI's environment passes them down: disabled by the element's own
    /// modifier or an ancestor's; hidden likewise (the box of the element that is hidden draws
    /// nothing, ModifierBox); skipped by accessibility tools when hidden or accessibilityHidden.
    private(set) var isDisabled = false
    private(set) var isHidden = false
    private(set) var isAccessibilityHidden = false
    /// labelsHidden, as SwiftUI's environment passes it down: a container's hides its controls' titles.
    private(set) var isLabelsHidden = false
    /// The states last applied to the WinUI object (applyStates).
    private var appliedEnabled: Bool?
    private var appliedAccessibilityHidden: Bool?
    /// True after the first sync.
    private(set) var hasSynced = false
    /// How far it grows in each axis when it expands: its frame's finite maximum, nil for no limit.
    private(set) var caps: (horizontal: Int?, vertical: Int?) = (nil, nil)

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
        if let view {
            do {
                box = try ModifierBox(content: view)
                box?.contentExpansion = UntrackedReads.perform { renderer.expansion(self) }
            } catch {
                ActionUIModel.shared.logger.log("RenderNode: \(error); \(element.type) shows without padding or frame", .error)
            }
        }
        // As sync computes it, untracked: a child is made during its parent's sync, whose
        // observation would take these reads as the parent's.
        let initial = UntrackedReads.perform { geometry }
        expansion = Self.expansion(UntrackedReads.perform { renderer.expansion(self) }, geometry: initial)
        caps = (initial.frame.horizontal.cap, initial.frame.vertical.cap)
        compression = Self.compression(UntrackedReads.perform { renderer.compression(self) }, geometry: initial)
    }

    /// The base modifiers the box and the text appearance read, from the current properties. A
    /// tracked read.
    private var baseModifiers: BaseModifiers {
        BaseModifiers(ActionUIRegistry.shared.baseModifierProperties(properties, forElementType: element.type))
    }

    /// The element's padding, frame and background, from its current properties. A tracked read.
    private var geometry: BoxGeometry {
        BoxGeometry(baseModifiers)
    }

    /// Applies the inherited states to the WinUI object, only when they changed: a control under a
    /// disabled or hidden element cannot be used (a hidden one draws nothing anyway, and so takes no
    /// keyboard focus); an element under a hidden or accessibilityHidden one is skipped by
    /// accessibility tools. Each node applies its own, since WinUI passes neither through panels.
    private func applyStates(to view: WinUIObject) {
        let enabled = !(isDisabled || isHidden)
        if appliedEnabled != enabled {
            appliedEnabled = enabled
            if !actionUIWinUIElementSetEnabled(view.pointer, enabled) {
                ActionUIModel.shared.logger.log("RenderNode: \(WinUIError.last("enabling an element"))", .error)
            }
        }
        if appliedAccessibilityHidden != isAccessibilityHidden {
            appliedAccessibilityHidden = isAccessibilityHidden
            if !actionUIWinUIElementSetAccessibilityHidden(view.pointer, isAccessibilityHidden) {
                ActionUIModel.shared.logger.log("RenderNode: \(WinUIError.last("hiding an element from accessibility tools"))", .error)
            }
        }
    }

    /// Applies the node's accessibility-hidden state to an inner object its renderer made (a label's
    /// title and icon, a button's icon and title, an image): WinUI's accessibility view hides one
    /// element, not its children, and ActionUI's panels are not seen by accessibility tools at all.
    func applyAccessibilityHidden(to inner: WinUIObject) {
        if !actionUIWinUIElementSetAccessibilityHidden(inner.pointer, isAccessibilityHidden) {
            ActionUIModel.shared.logger.log("RenderNode: \(WinUIError.last("hiding an element from accessibility tools"))", .error)
        }
    }

    /// Draws the WinUI object's text with the node's appearance, only when it changed: for the
    /// renderers of elements that show text (Text, Button, Toggle, TextField).
    func applyTextAppearance(to view: WinUIObject, what: String) {
        guard appliedAppearance != textAppearance else { return }
        appliedAppearance = textAppearance
        textAppearance.apply(to: view, what: what)
    }

    private static func expansion(_ renderer: Expansion, geometry: BoxGeometry) -> Expansion {
        let frame = geometry.frameExpansion
        var expansion: Expansion = []
        if frame.horizontal ?? renderer.contains(.horizontal) { expansion.insert(.horizontal) }
        if frame.vertical ?? renderer.contains(.vertical) { expansion.insert(.vertical) }
        return expansion
    }

    /// The renderer's compression, without the axes a fixed frame sizes: SwiftUI's fixed frame
    /// keeps its size in a stack, so the stack need not measure it for its smallest size.
    private static func compression(_ renderer: Expansion, geometry: BoxGeometry) -> Expansion {
        var compression = renderer
        if geometry.frame.horizontal.fixed != nil { compression.remove(.horizontal) }
        if geometry.frame.vertical.fixed != nil { compression.remove(.vertical) }
        return compression
    }

    // MARK: Syncing

    /// Makes the WinUI object show the model, and watches what that read.
    func sync() {
        guard isAttached, let view else { return }
        var expansionChanged = false
        let previousAppearance = textAppearance
        let previousStates = (isDisabled, isHidden, isAccessibilityHidden, isLabelsHidden)
        withObservationTracking {
            let modifiers = baseModifiers
            // Before the renderer's update, which draws the text with it.
            textAppearance = (parent?.textAppearance ?? TextAppearance()).applying(modifiers)
            isDisabled = (parent?.isDisabled ?? false) || modifiers.disabled == true
            isHidden = (parent?.isHidden ?? false) || modifiers.hidden
            isAccessibilityHidden = isHidden || (parent?.isAccessibilityHidden ?? false) || modifiers.accessibilityHidden == true
            isLabelsHidden = (parent?.isLabelsHidden ?? false) || modifiers.labelsHidden
            renderer.update(view, self)
            applyStates(to: view)
            let geometry = BoxGeometry(modifiers)
            box?.contentExpansion = renderer.expansion(self)
            box?.update(geometry)
            let newExpansion = Self.expansion(renderer.expansion(self), geometry: geometry)
            let newCaps = (geometry.frame.horizontal.cap, geometry.frame.vertical.cap)
            let newCompression = Self.compression(renderer.compression(self), geometry: geometry)
            expansionChanged = newExpansion != expansion || newCaps != caps || newCompression != compression
            expansion = newExpansion
            caps = newCaps
            compression = newCompression
        } onChange: { [weak self] in
            // The model is main-actor isolated, so changes, and this call, happen on the main
            // thread, before the new value is stored.
            MainActor.assumeIsolated {
                guard let self else { return }
                SyncScheduler.shared.markDirty(self)
            }
        }
        // The parent laid this node out with its old expansion, caps or compression (and a stack's
        // own come from its children's).
        if expansionChanged, let parent {
            SyncScheduler.shared.markDirty(parent)
        }
        let created = unsyncedChildren
        unsyncedChildren = []
        // The children inherit the appearance; new ones read it in their first sync below (and are
        // not marked, as the GTK renderer skips them).
        if hasSynced && (textAppearance != previousAppearance || (isDisabled, isHidden, isAccessibilityHidden, isLabelsHidden) != previousStates) {
            let new = Set(created.map(ObjectIdentifier.init))
            for child in childNodes.values where !new.contains(ObjectIdentifier(child)) {
                SyncScheduler.shared.markDirty(child)
            }
        }
        hasSynced = true
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
