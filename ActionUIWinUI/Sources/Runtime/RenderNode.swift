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
    /// The object accessibility tools read as the element (its renderer's accessibleObject).
    package var accessibleView: WinUIObject? { view.map { renderer.accessibleObject($0, self) } }
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
    /// buttonStyle, as SwiftUI's environment passes it down: the element's own, else its nearest
    /// ancestor's (a container's styles the buttons in it); automatic sets none.
    private(set) var buttonStyle: BaseModifiers.ButtonStyleName?
    /// controlSize, as SwiftUI's environment passes it down: the element's own, else its nearest
    /// ancestor's (ControlSizing).
    private(set) var controlSize: BaseModifiers.ControlSizeName?
    /// The element's own tint last given to its WinUI object's resources (applyTint); nil: none.
    private var appliedTint: ActionUIWinUIColor?
    /// The accessibility texts and tooltip last applied (applyAccessibility), the name with the
    /// renderer's default; each nil: none applied.
    private var appliedAccessibility = AccessibilityTexts()
    /// Whether the box appeared, when the element declares onAppearActionID or onDisappearActionID
    /// (NodeAppearance+WinUI.swift).
    private var appearance: AppearanceWatch?
    /// The keyboard shortcut last given to the accessible object (KeyboardShortcut+WinUI.swift).
    private var appliedShortcut: WindowsShortcut?
    /// The states last applied to the WinUI object (applyStates).
    private var appliedEnabled: Bool?
    private var appliedAccessibilityHidden: Bool?
    /// True after the first sync.
    private(set) var hasSynced = false
    /// How far it grows in each axis when it expands: its frame's finite maximum, nil for no limit.
    private(set) var caps: (horizontal: Int?, vertical: Int?) = (nil, nil)
    /// Whether the element takes no place in its container (ActionUIWinUIRenderer.takesNoPlace).
    private(set) var takesNoPlace = false

    /// What the renderer keeps for this element instance beside its WinUI object (a stack's
    /// StackLayout), as on Linux.
    var state: AnyObject?

    /// False once the node left the tree (its element was removed, or its window went away).
    private(set) var isAttached = true
    private(set) var childNodes: [Int: RenderNode] = [:]
    /// The child nodes in their elements' order, as the last syncChildren left them.
    package private(set) var orderedChildren: [RenderNode] = []
    /// The template instances this node shows (a List's rows), in the order they were made: not
    /// child nodes, since every row has the template's ids. The container keeps them in its rows'
    /// order and releases them (releaseTemplateNode).
    package private(set) var templateNodes: [RenderNode] = []
    /// Nodes of elements this node shows elsewhere than among its children (its toolbar items'
    /// contents): made like children, so they inherit its environment, and synced as they are.
    package private(set) var auxiliaryNodes: [RenderNode] = []
    /// True for a background or overlay view's node: in its element's box, not among its children,
    /// so the element is not the stack it is in (StackViews.parentAxis, parentArrangement).
    private(set) var isDecoration = false
    /// The toolbar the element declares (its "toolbar" items), shown in the window's command row.
    private(set) var toolbar: NodeToolbar?
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
        takesNoPlace = UntrackedReads.perform { renderer.takesNoPlace(self) }
        toolbar = NodeToolbar.make(for: self)
        appearance = NodeAppearance.watch(self)
        makeDecorations()
    }

    /// The element's background and overlay views (its "background" and "overlay" subviews), made as
    /// auxiliary nodes and placed in its box; none on a Group or a Section, whose modifiers SwiftUI
    /// applies to each child. They inherit this node's environment (the Linux renderer gives them
    /// the parent's, with the element's font and colors left out, as SwiftUI applies those first).
    private func makeDecorations() {
        guard let box, element.type != "Group", element.type != "Section" else { return }
        func decoration(_ key: String) -> ModifierBox.Decoration? {
            guard let subview = element.subviews?[key] as? any ActionUIElementBase else { return nil }
            let node = auxiliaryNode(for: subview)
            node.isDecoration = true
            guard let view = node.outerView else { return nil }
            return ModifierBox.Decoration(view: view, expansion: { [weak node] in node?.expansion ?? [] })
        }
        box.setDecorations(background: decoration("background"), overlay: decoration("overlay"))
    }

    /// The base modifiers the box and the text appearance read, from the current properties. A
    /// tracked read.
    private var baseModifiers: BaseModifiers {
        BaseModifiers(ActionUIRegistry.shared.baseModifierProperties(properties, forElementType: element.type))
    }

    /// The element's padding, frame and background, from its current properties. A tracked read.
    private var geometry: BoxGeometry {
        boxGeometry(baseModifiers)
    }

    /// The box geometry for `base`, the element's base modifiers: without its padding and frame in a
    /// ControlGroup, none for a Group.
    private func boxGeometry(_ base: BaseModifiers) -> BoxGeometry {
        // A Group's modifiers apply to each child, in the boxes it puts them in (Group+WinUI.swift).
        if element.type == "Group" {
            return BoxGeometry()
        }
        var modifiers = base
        // In a ControlGroup a child's padding and frame do not apply: macOS draws the group from its
        // buttons' titles (measured on macOS 27: padded buttons are as wide as without, a button framed
        // 100 wide keeps its own width), so the buttons stay joined.
        if parent?.element.type == "ControlGroup", !isDecoration {
            modifiers.padding = nil
            modifiers.frame = nil
        }
        return BoxGeometry(modifiers)
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

    /// Gives the element's accessible object (the renderer's accessibleObject) its name for
    /// accessibility tools (accessibilityLabel, else the renderer's default name), hint (else the help
    /// text, which SwiftUI's help also gives them, as on Linux) and identifier (UI Automation's
    /// AutomationId, which test tools find it by), and the element's object the help as its tooltip.
    /// The name is written on every sync while there is one, as on Linux: a control can write its name
    /// itself (an Expander's title) in the renderer's update before this; WinUI skips a write of the
    /// name it has. The others only when they changed. With neither a label nor a default name, the
    /// control's own (from its content) is left, or restored once when one is taken away. Not yet: an
    /// element drawn in ActionUI's own panels with no single control to read (a Label, a Stepper, a
    /// DatePicker) gets them on its panel, which accessibility tools do not see (only the tooltip
    /// shows).
    private func applyAccessibility(_ texts: AccessibilityTexts, to view: WinUIObject) {
        let logger = ActionUIModel.shared.logger
        let target = renderer.accessibleObject(view, self)
        var texts = texts
        texts.label = texts.label ?? renderer.defaultAccessibleName(self).flatMap { $0.isEmpty ? nil : $0 }
        let applied = appliedAccessibility
        appliedAccessibility = texts
        if texts.label != nil || applied.label != nil, !actionUIWinUIElementSetAccessibleName(target.pointer, texts.label) {
            logger.log("RenderNode: \(WinUIError.last("naming an element for accessibility tools"))", .error)
        }
        if texts.hint != applied.hint, !actionUIWinUIElementSetAccessibilityHint(target.pointer, texts.hint) {
            logger.log("RenderNode: \(WinUIError.last("giving an element its accessibility hint"))", .error)
        }
        if texts.identifier != applied.identifier, !actionUIWinUIElementSetAccessibilityIdentifier(target.pointer, texts.identifier) {
            logger.log("RenderNode: \(WinUIError.last("giving an element its accessibility identifier"))", .error)
        }
        if texts.help != applied.help, !actionUIWinUIElementSetToolTip(view.pointer, texts.help) {
            logger.log("RenderNode: \(WinUIError.last("giving an element its tooltip"))", .error)
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

    /// The element's own tint as the accent of its WinUI object and what it holds: the brushes
    /// WinUI's controls take their accent from, in the object's resources, which the controls in
    /// it look up when their templates are applied (WinUI's lightweight styling). A tint that is no
    /// color (a semantic style) is the system accent. Descendants need none of their own: WinUI
    /// looks the brushes up through the tree.
    private func applyTint(_ tint: String?, to view: WinUIObject) {
        var color: ActionUIWinUIColor?
        if case let .color(value)? = Paint.parse(tint, role: .background) {
            color = value
        }
        let same: Bool
        switch (color, appliedTint) {
        case (nil, nil): same = true
        case let (a?, b?): same = a.red == b.red && a.green == b.green && a.blue == b.blue && a.alpha == b.alpha
        default: same = false
        }
        guard !same else { return }
        appliedTint = color
        let set = withUnsafePointer(to: color ?? ActionUIWinUIColor()) { pointer in
            actionUIWinUIElementSetAccent(view.pointer, color == nil ? nil : pointer)
        }
        if !set {
            ActionUIModel.shared.logger.log("tint: \(WinUIError.last("setting the accent of a \(element.type)"))", .error)
        }
    }

    static func expansion(_ renderer: Expansion, geometry: BoxGeometry) -> Expansion {
        let frame = geometry.frameExpansion
        var expansion: Expansion = []
        if frame.horizontal ?? renderer.contains(.horizontal) { expansion.insert(.horizontal) }
        if frame.vertical ?? renderer.contains(.vertical) { expansion.insert(.vertical) }
        return expansion
    }

    /// The renderer's compression, without the axes a fixed frame sizes: SwiftUI's fixed frame
    /// keeps its size in a stack, so the stack need not measure it for its smallest size.
    static func compression(_ renderer: Expansion, geometry: BoxGeometry) -> Expansion {
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
        let previousStates = (isDisabled, isHidden, isAccessibilityHidden, isLabelsHidden, buttonStyle, controlSize)
        withObservationTracking {
            let modifiers = baseModifiers
            // Before the renderer's update, which draws the text with it.
            textAppearance = (parent?.textAppearance ?? TextAppearance()).applying(modifiers)
            isDisabled = (parent?.isDisabled ?? false) || modifiers.disabled == true
            isHidden = (parent?.isHidden ?? false) || modifiers.hidden
            isAccessibilityHidden = isHidden || (parent?.isAccessibilityHidden ?? false) || modifiers.accessibilityHidden == true
            isLabelsHidden = (parent?.isLabelsHidden ?? false) || modifiers.labelsHidden
            // automatic sets none, so one from further up stays (as on Apple and Linux).
            if let own = modifiers.buttonStyle, own != .automatic {
                buttonStyle = own
            } else {
                buttonStyle = parent?.buttonStyle
            }
            controlSize = modifiers.controlSize ?? parent?.controlSize
            // Before the renderer's update, which puts the children in the object: in a shown window
            // a control takes its built-in style, and that style's setters their brushes, as it is
            // put in.
            applyTint(modifiers.tint, to: view)
            renderer.update(view, self)
            toolbar?.update()
            applyStates(to: view)
            applyAccessibility(AccessibilityTexts(modifiers), to: view)
            appliedShortcut = Self.applyShortcut(modifiers.keyboardShortcut, to: renderer.accessibleObject(view, self),
                                                 applied: appliedShortcut)
            let geometry = boxGeometry(modifiers)
            box?.contentExpansion = renderer.expansion(self)
            box?.update(geometry)
            let newExpansion = Self.expansion(renderer.expansion(self), geometry: geometry)
            let newCaps = (geometry.frame.horizontal.cap, geometry.frame.vertical.cap)
            let newCompression = Self.compression(renderer.compression(self), geometry: geometry)
            let newTakesNoPlace = renderer.takesNoPlace(self)
            expansionChanged = newExpansion != expansion || newCaps != caps || newCompression != compression
                || newTakesNoPlace != takesNoPlace
            expansion = newExpansion
            caps = newCaps
            compression = newCompression
            takesNoPlace = newTakesNoPlace
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
        if hasSynced && (textAppearance != previousAppearance || (isDisabled, isHidden, isAccessibilityHidden, isLabelsHidden, buttonStyle, controlSize) != previousStates) {
            let new = Set(created.map(ObjectIdentifier.init))
            for child in Array(childNodes.values) + templateNodes + auxiliaryNodes where !new.contains(ObjectIdentifier(child)) {
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

    /// The view model of a child made for `element`: its registered one, or inside a template row one
    /// of its own.
    private func childModel(for element: any ActionUIElementBase) -> ViewModel {
        if let context = model.templateContext {
            // Inside a template row the child is a blueprint too, shown with the row's data in a view
            // model of its own, as on Apple (TemplateHelper) and Linux.
            return Self.templateModel(element, context)
        } else if let registered = windowModel.viewModels[element.id] {
            return registered
        }
        ActionUIModel.shared.logger.log("RenderNode: no view model for element \(element.id) (\(element.type)) in window \(windowModel.windowUUID); rendering it with an empty one", .warning)
        return ViewModel()
    }

    /// A node for one row of a template container: `template` shown with the row's data, in a view
    /// model of its own whose TemplateContext names this node as the parent (the id its actions
    /// report) and the row's index and data. Synced at the end of this node's sync, like a new child.
    /// The container releases it (releaseTemplateNode) when its row goes or changes.
    func templateRowNode(_ template: any ActionUIElementBase, row: [String], rowIndex: Int) -> RenderNode {
        let context = TemplateContext(parentID: element.id, rowIndex: rowIndex, row: row)
        let node = RenderNode(element: template, model: Self.templateModel(template, context), windowModel: windowModel, parent: self)
        templateNodes.append(node)
        unsyncedChildren.append(node)
        return node
    }

    /// A node for `element` shown outside this node's children (a toolbar item's content), with the
    /// element's registered view model; synced at the end of this node's sync, like a new child. The
    /// caller releases it (releaseAuxiliaryNode) when it no longer shows it.
    func auxiliaryNode(for element: any ActionUIElementBase) -> RenderNode {
        let node = RenderNode(element: element, model: childModel(for: element), windowModel: windowModel, parent: self)
        auxiliaryNodes.append(node)
        unsyncedChildren.append(node)
        return node
    }

    /// Takes an auxiliary node out of the tree.
    func releaseAuxiliaryNode(_ node: RenderNode) {
        node.detach()
        auxiliaryNodes.removeAll { $0 === node }
        unsyncedChildren.removeAll { $0 === node }
    }

    /// Takes a template instance out of the tree.
    func releaseTemplateNode(_ node: RenderNode) {
        node.detach()
        templateNodes.removeAll { $0 === node }
        // Made outside this node's sync (a lazy stack's row, in a layout pass), it would otherwise stay
        // here until that sync, however many rows came and went meanwhile.
        unsyncedChildren.removeAll { $0 === node }
    }

    /// A template instance's view model: the element's properties with the row's data substituted.
    private static func templateModel(_ element: any ActionUIElementBase, _ context: TemplateContext) -> ViewModel {
        let model = ViewModel()
        model.templateContext = context
        model.seedProperties(TemplateHelper.instanceProperties(of: element, row: context.row, logger: ActionUIModel.shared.logger))
        return model
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
        if let appearance {
            NodeAppearance.left(self, appearance)
        }
        isAttached = false
        orderedChildren = []
        for child in childNodes.values {
            child.detach()
        }
        for node in templateNodes {
            node.detach()
        }
        templateNodes = []
        toolbar?.detach()
        for node in auxiliaryNodes {
            node.detach()
        }
        auxiliaryNodes = []
    }
}

/// An element's accessibility texts and tooltip from its modifiers: each nil when absent or empty.
struct AccessibilityTexts: Equatable {
    var label: String?
    var hint: String?
    var identifier: String?
    var help: String?

    init() {}

    init(_ modifiers: BaseModifiers) {
        func text(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        label = text(modifiers.accessibilityLabel)
        help = text(modifiers.help)
        hint = text(modifiers.accessibilityHint) ?? help
        identifier = text(modifiers.accessibilityIdentifier)
    }
}
