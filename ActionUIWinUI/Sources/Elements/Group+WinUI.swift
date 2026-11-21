// Sources/Elements/Group+WinUI.swift
/*
 Group on WinUI: its children laid out as its parent stack's own, as SwiftUI's Group has no layout of
 its own, following the Linux renderer (Group+Adwaita.swift). Measured on macOS 27 (the layout parity
 fixtures group-*): a Group's modifiers apply to each child, not to the Group as a whole, so a Group
 padded 10 pads each child 10 and a Group framed 50 x 30 puts each child in a 50 x 30 frame.

 - Each child's box sits in a box of the Group's (a ModifierBox) that takes the Group's padding,
   frame, background, opacity and hidden; the Group's own box takes none of them (RenderNode). Its
   children inherit the rest (font, foregroundStyle, disabled) from it, as from any parent.
 - The boxes are a column or a row along the axis of the stack the Group is in, with that stack's
   spacing and alignment (a VStack's or an HStack's own, a Form's rows, a GroupBox's or a Section's
   column, a LabeledContent's row, an enclosing Group's), so they sit as that stack's children
   would; elsewhere (a window's root, a ScrollView) a column with no spacing, centered, as on Linux.
   A Spacer or a Divider in a Group takes the axis of the stack the Group is in. A Group with nothing
   to show (no children, a template with no rows) takes no place, as on Apple and Linux.
 - The template form shows one child per content row (setElementRows): the template shown with the
   row's data, as on Apple.

 Not yet: the boxes laid out among the stack's own children (Linux does): a Spacer in a Group shares
 the stack's room with the Group's siblings as one of the Group's children, not as the stack's; in a
 ZStack, the children overlaid (a column for now); in an HSplitView or a VSplitView each child a pane
 of its own, and in a Grid's row each child a column of its own (the Group is one pane, one cell); in
 a Form, its controls as the Form's rows, their titles in the Form's label column (the Group is one
 row without a title).
*/

import CWinUI

/// A Group's column (or row) and the box it puts around each child, by child node.
@MainActor final class GroupState {
    let stack: StackLayout
    var boxes: [ObjectIdentifier: ModifierBox] = [:]
    /// True after the first update: before it the Group has made no child nodes yet.
    var hasUpdated = false

    init(stack: StackLayout) {
        self.stack = stack
    }
}

extension Group: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let stack = try StackLayout(axis: StackViews.parentAxis(node) ?? .vertical)
        node.state = GroupState(stack: stack)
        return stack.panel.object
    }

    /// The box geometry the Group gives each child: its own modifiers. A tracked read.
    static func childGeometry(_ node: RenderNode) -> BoxGeometry {
        BoxGeometry(BaseModifiers(ActionUIRegistry.shared.baseModifierProperties(node.properties, forElementType: node.element.type)))
    }

    /// How a child grows in its box of `geometry`, as a node grows in its own box: the box's frame
    /// decides an axis it sets (its cap too: a maxWidth of infinity has none, whatever the child's),
    /// the child the others.
    static func boxed(_ child: RenderNode, _ geometry: BoxGeometry) -> (expansion: Expansion, cap: (horizontal: Int?, vertical: Int?), compression: Expansion) {
        func cap(_ frame: FrameAxis, _ childCap: Int?) -> Int? {
            frame.expands != nil ? frame.cap : childCap
        }
        return (RenderNode.expansion(child.expansion, geometry: geometry),
                (cap(geometry.frame.horizontal, child.caps.horizontal), cap(geometry.frame.vertical, child.caps.vertical)),
                RenderNode.compression(child.compression, geometry: geometry))
    }

    /// A Group with nothing to show (no children, a template with no rows, only EmptyViews) takes no
    /// place in its stack, no spacing either, as on Apple and Linux. Before its first update it has
    /// made no child nodes, and takes its place, so a Group with children is not left out of its
    /// stack's first layout.
    static func takesNoPlace(_ node: RenderNode) -> Bool {
        guard let state = node.state as? GroupState, state.hasUpdated else { return false }
        return state.boxes.isEmpty
    }

    /// The Group grows as a stack of its boxes does (StackViews.childrenExpansion).
    static func expansion(_ node: RenderNode) -> Expansion {
        let geometry = childGeometry(node)
        var expansion: Expansion = []
        for child in node.orderedChildren + node.templateNodes where !child.takesNoPlace {
            let box = boxed(child, geometry)
            if box.expansion.contains(.horizontal) && box.cap.horizontal == nil { expansion.insert(.horizontal) }
            if box.expansion.contains(.vertical) && box.cap.vertical == nil { expansion.insert(.vertical) }
        }
        return expansion
    }

    static func compression(_ node: RenderNode) -> Expansion {
        let geometry = childGeometry(node)
        return (node.orderedChildren + node.templateNodes).reduce(into: Expansion()) { $0.formUnion(boxed($1, geometry).compression) }
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? GroupState else { return }
        let arrangement = StackViews.parentArrangement(node)
        StackViews.configure(state.stack, spacing: arrangement.spacing, alignment: arrangement.alignment)
        let geometry = childGeometry(node)
        var boxes: [ObjectIdentifier: ModifierBox] = [:]
        var items: [StackLayout.Item] = []
        for child in state.stack.templateRows.contentNodes(of: node) where !child.takesNoPlace {
            guard let content = child.outerView else { continue }
            let key = ObjectIdentifier(child)
            var box = state.boxes[key]
            // A node for another child under a reused id (a template row made again): a new box around it.
            if let old = box, old.content !== content {
                release(old)
                state.boxes[key] = nil
                box = nil
            }
            if box == nil {
                do {
                    box = try ModifierBox(content: content)
                } catch {
                    ActionUIModel.shared.logger.log("Group: \(error)", .error)
                    continue
                }
            }
            guard let box else { continue }
            box.contentExpansion = child.expansion
            box.update(geometry)
            boxes[key] = box
            let grows = boxed(child, geometry)
            let spacerMinimum = child.element.type == "Spacer" ? (Spacer.Props(child.properties).minLength ?? Spacer.defaultMinLength) : nil
            items.append(StackLayout.Item(view: box.panel.object, spacerMinimum: spacerMinimum, expansion: grows.expansion, cap: grows.cap,
                                          compressible: grows.compression))
        }
        let gone = state.boxes.filter { boxes[$0.key] == nil }.map(\.value)
        state.boxes = boxes
        state.hasUpdated = true
        state.stack.setItems(items)
        // After the stack let go of them: their children may be put in other boxes.
        for box in gone {
            release(box)
        }
    }

    /// Takes a box's content out of it, so the content can be put elsewhere.
    private static func release(_ box: ModifierBox) {
        guard let index = box.group.children.firstIndex(where: { $0 === box.content }) else { return }
        do {
            try box.group.remove(at: index)
        } catch {
            ActionUIModel.shared.logger.log("Group: \(error)", .error)
        }
    }
}
