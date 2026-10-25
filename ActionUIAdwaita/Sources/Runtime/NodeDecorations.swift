// Sources/Runtime/NodeDecorations.swift
/*
 A view's background and overlay subviews on GTK (SwiftUI's .background(alignment:) { view } and
 .overlay(alignment:) { view }), placed where the Apple renderer's modifier order puts them
 (View.applyModifiers):

 - The background view is applied after the frame and the background color, before cornerRadius,
   clipShape and the transforms: it lies behind the element in its content group, offered the
   framed size, rounded and clipped with it, and moved by offset, rotation and scale with it.
 - The overlay view is applied after the transforms and the border: it lies over the element in
   its outer box, offered the frame at its place in the layout (not moved by offset, rotation or
   scale, not clipped).

 Each is offered the frame's size: a view that expands (a Color, a shape) fills it, another takes
 its own size, up to it, and is aligned in it by backgroundAlignment or overlayAlignment (center by
 default). Neither changes the element's size. A background view is drawn before the element and
 an overlay after it, so a click goes to the overlay, then the element, then the background.

 Only the views the element declares when its node is made are shown, and none on a Group or a
 Section, whose modifiers SwiftUI applies to each child.
*/

import CAdwaita

/// On a background or overlay view's box: which it is, and its alignment in the frame.
@MainActor
final class DecorationMarker {
    enum Place {
        case background, overlay
    }

    let place: Place
    var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)

    init(_ place: Place) {
        self.place = place
    }
}

let decorationMarkerKey = AttachKey<DecorationMarker>("actionui-decoration")

@MainActor
final class NodeDecorations {
    private var background: RenderNode?
    private var overlay: RenderNode?

    /// A node's background and overlay views, or nil when its element declares neither.
    static func make(for node: RenderNode) -> NodeDecorations? {
        let background = node.element.subviews?["background"] as? any ActionUIElementBase
        let overlay = node.element.subviews?["overlay"] as? any ActionUIElementBase
        guard background != nil || overlay != nil, let content = ModifierBox.content(of: node.outerWidget) else { return nil }
        // Not on a Group or a Section: SwiftUI applies their modifiers to each child, and the
        // Group's box spans its stack (Group+Adwaita), so one view there would be neither placed
        // nor drawn, and would take the clicks of the stack's other children.
        guard attached(on: UnsafeMutableRawPointer(node.widget), key: groupMarkerKey) == nil else {
            ActionUIModel.shared.logger.log("NodeDecorations: background and overlay views on a \(node.element.type) are not shown on Linux", .warning)
            return nil
        }
        let decorations = NodeDecorations()
        if let background {
            let view = node.auxiliaryNode(for: background)
            attach(DecorationMarker(.background), to: UnsafeMutableRawPointer(view.outerWidget), key: decorationMarkerKey)
            // First in the content group: drawn behind the element.
            gtk_widget_insert_after(view.outerWidget, content, nil)
            decorations.background = view
        }
        if let overlay {
            let view = node.auxiliaryNode(for: overlay)
            attach(DecorationMarker(.overlay), to: UnsafeMutableRawPointer(view.outerWidget), key: decorationMarkerKey)
            // Last in the outer box: drawn over the content group.
            gtk_widget_insert_before(view.outerWidget, node.outerWidget, nil)
            decorations.overlay = view
        }
        return decorations
    }

    /// The views' nodes, for the environment changes their parent passes down.
    var nodes: [RenderNode] {
        [background, overlay].compactMap { $0 }
    }

    /// The views' alignments from the element's modifiers; a change places them again. The
    /// element's font, foregroundStyle, tint and disabled reach them too, as SwiftUI's environment
    /// reaches a background or overlay applied after them: on GTK these sit on the element's
    /// widget, which the views are not inside.
    func update(_ modifiers: BaseModifiers) {
        Self.align(background, ModifierBox.alignmentAxes(modifiers.backgroundAlignment))
        Self.align(overlay, ModifierBox.alignmentAxes(modifiers.overlayAlignment))
        for view in nodes {
            ModifierBox.applyText(view.outerWidget, modifiers)
            Gtk.Widget(view.outerWidget).isSensitive = modifiers.disabled != true
        }
    }

    private static func align(_ view: RenderNode?, _ alignment: (horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment)) {
        guard let view, let marker = attached(on: UnsafeMutableRawPointer(view.outerWidget), key: decorationMarkerKey),
              marker.alignment != alignment else { return }
        marker.alignment = alignment
        if let parent = gtk_widget_get_parent(view.outerWidget) {
            gtk_widget_queue_allocate(parent)
        }
    }

    /// The node left the tree: the views leave it too.
    func detach() {
        for view in [background, overlay].compactMap({ $0 }) {
            view.detach()
            if gtk_widget_get_parent(view.outerWidget) != nil {
                gtk_widget_unparent(view.outerWidget)
            }
        }
        background = nil
        overlay = nil
    }
}
