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
 The element's onHover, contextMenu, onDrop and container tap cover the overlay too
 (pointerAreas), as SwiftUI applies them after it.

 The views inherit what SwiftUI's modifier order gives them: the element's parent's environment
 with the element's settings applied after the view (environment(for:of:)), and the element's
 hidden state; not its font, foregroundStyle, tint or disabled, which SwiftUI applies before them.

 A safe area inset view (SwiftUI's .safeAreaInset(edge:alignment:spacing:)) is applied after the
 overlay: it lies along an edge of the element's outer box, which gives the element's frame the
 rest of its room, less the inset and its spacing (ModifierBox). Across the edge it fills when it
 expands, else it takes its own size, aligned by safeAreaAlignment; like the overlay it is not
 moved by the transforms, and it inherits as the overlay does.

 Only the views the element declares when its node is made are shown, and none on a Group or a
 Section, whose modifiers SwiftUI applies to each child.
*/

import CAdwaita

/// On a background, overlay or safe area inset view's box: which it is, and its alignment in the
/// frame (an inset's across its edge).
@MainActor
final class DecorationMarker {
    enum Place {
        case background, overlay, inset
    }

    /// The edge a safe area inset view lies along.
    enum Edge: String {
        case top, bottom, leading, trailing
    }

    let place: Place
    var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)
    /// A safe area inset view's edge and its distance from the element's frame.
    var edge = Edge.bottom
    var spacing = Int(StackLayout.defaultSpacing)

    /// Whether a safe area inset view lies along `orientation` (a top or bottom one vertically),
    /// adding its length to the element's.
    func liesAlong(_ orientation: GtkOrientation) -> Bool {
        (edge == .top || edge == .bottom) == (orientation == GTK_ORIENTATION_VERTICAL)
    }
    /// Hidden from assistive technologies with the element (hidden, accessibilityHidden).
    var hidden = false

    init(_ place: Place) {
        self.place = place
    }
}

let decorationMarkerKey = AttachKey<DecorationMarker>("actionui-decoration")

@MainActor
final class NodeDecorations {
    private var background: RenderNode?
    private(set) var overlay: RenderNode?
    private(set) var inset: RenderNode?

    /// A node's background, overlay and safe area inset views, or nil when its element declares
    /// none.
    static func make(for node: RenderNode) -> NodeDecorations? {
        let background = node.element.subviews?["background"] as? any ActionUIElementBase
        let overlay = node.element.subviews?["overlay"] as? any ActionUIElementBase
        let inset = node.element.subviews?["safeAreaInset"] as? any ActionUIElementBase
        guard background != nil || overlay != nil || inset != nil,
              let content = ModifierBox.content(of: node.outerWidget) else { return nil }
        // Not on a Group or a Section: SwiftUI applies their modifiers to each child, and the
        // Group's box spans its stack (Group+Adwaita), so one view there would be neither placed
        // nor drawn, and would take the clicks of the stack's other children.
        guard attached(on: UnsafeMutableRawPointer(node.widget), key: groupMarkerKey) == nil else {
            ActionUIModel.shared.logger.log("NodeDecorations: background and overlay views on a \(node.element.type) are not shown on Linux", .warning)
            return nil
        }
        let decorations = NodeDecorations()
        if let background {
            let view = node.auxiliaryNode(for: background, decoration: .background)
            // First in the content group: drawn behind the element.
            gtk_widget_insert_after(view.outerWidget, content, nil)
            mark(view, .background, in: content)
            decorations.background = view
        }
        if let overlay {
            let view = node.auxiliaryNode(for: overlay, decoration: .overlay)
            // Last in the outer box: drawn over the content group.
            gtk_widget_insert_before(view.outerWidget, node.outerWidget, nil)
            mark(view, .overlay, in: node.outerWidget)
            decorations.overlay = view
        }
        if let inset {
            let view = node.auxiliaryNode(for: inset, decoration: .inset)
            // In the outer box beside the frame, which ModifierBox lays out in the rest of the box.
            gtk_widget_insert_before(view.outerWidget, node.outerWidget, nil)
            mark(view, .inset, in: node.outerWidget)
            decorations.inset = view
        }
        return decorations
    }

    /// Marks a view's box, a child of `parent`, as a background or overlay view. GTK shows a
    /// widget to assistive technologies again whenever it maps, after the widget's own "map"
    /// handlers run, so a view hidden with its element is hidden again by a "map" handler on its
    /// parent: it runs after the parent's default handler, which maps the parent's children.
    private static func mark(_ view: RenderNode, _ place: DecorationMarker.Place, in parent: WidgetPointer) {
        let box: WidgetPointer = view.outerWidget
        let marker = DecorationMarker(place)
        attach(marker, to: UnsafeMutableRawPointer(box), key: decorationMarkerKey)
        // The marker lives as long as the box it is attached to, so once the box is gone the
        // handler does not touch it.
        connectSignal(UnsafeMutableRawPointer(parent), "map", .instanceOnly) { [weak marker] in
            guard marker?.hidden == true, gtk_widget_get_mapped(box) != 0 else { return }
            ModifierBox.setHidden(OpaquePointer(box), true)
        }
    }

    /// The environment a background, overlay or safe area inset view inherits: the element's
    /// parent's, with only the element's settings SwiftUI applies after the view
    /// (View.applyModifiers' order): textSelection and multilineTextAlignment come after the
    /// background and before the overlay and the inset, buttonStyle and labelsHidden after all
    /// three. A tracked read of the element's properties.
    static func environment(for place: DecorationMarker.Place, of element: RenderNode) -> Environment {
        var modifiers = BaseModifiers(element.properties)
        if place != .background {
            modifiers.multilineTextAlignment = nil
            modifiers.textSelection = nil
        }
        return (element.parent?.environment ?? Environment()).applying(modifiers)
    }

    /// Where the pointer reaches the element: its frame (the box's content group) and its overlay
    /// and safe area inset views' boxes. SwiftUI applies onHover, contextMenu, onDrop and the
    /// container tap after the overlay and the inset, so they cover them too; on GTK those views
    /// are beside the frame, not inside it.
    static func pointerAreas(_ node: RenderNode) -> [WidgetPointer] {
        let box: WidgetPointer = node.outerWidget
        let frame = ModifierBox.content(of: box) ?? box
        let views: [WidgetPointer] = [node.decorations?.overlay, node.decorations?.inset].compactMap { $0?.outerWidget }
        return [frame] + views
    }

    /// The views' nodes, for the environment changes their parent passes down.
    var nodes: [RenderNode] {
        [background, overlay, inset].compactMap { $0 }
    }

    /// The views' alignments from the element's modifiers; a change places them again. Its
    /// hidden state hides them from assistive technologies, as SwiftUI applies hidden and
    /// accessibilityHidden after them. The element's font, foregroundStyle, tint and disabled do
    /// not reach them, as SwiftUI applies those before them (measured: an overlay after
    /// foregroundStyle draws in the default style, one after disabled is enabled); on GTK they
    /// sit on the element's widget, which the views are not inside.
    func update(_ modifiers: BaseModifiers) {
        Self.align(background, ModifierBox.alignmentAxes(modifiers.backgroundAlignment))
        Self.align(overlay, ModifierBox.alignmentAxes(modifiers.overlayAlignment))
        if let inset {
            Self.placeInset(inset)
        }
        let hidden = modifiers.hidden || modifiers.accessibilityHidden == true
        for view in nodes {
            // Hidden from assistive technologies with the element, as SwiftUI's hidden and
            // accessibilityHidden, applied after the views, hide them too.
            if let marker = attached(on: UnsafeMutableRawPointer(view.outerWidget), key: decorationMarkerKey), marker.hidden != hidden {
                marker.hidden = hidden
                ModifierBox.setHidden(OpaquePointer(view.outerWidget), hidden || gtk_widget_get_mapped(view.outerWidget) == 0)
            }
        }
    }

    /// A safe area inset view's edge, spacing and alignment, from its own properties (as the
    /// Apple renderer reads them): safeAreaEdge (bottom by default), safeAreaSpacing (SwiftUI's
    /// 8 by default, measured) and safeAreaAlignment across the edge (centered by default).
    private static func placeInset(_ view: RenderNode) {
        guard let marker = attached(on: UnsafeMutableRawPointer(view.outerWidget), key: decorationMarkerKey) else { return }
        let properties = view.properties
        let edge = (properties["safeAreaEdge"] as? String).flatMap(DecorationMarker.Edge.init(rawValue:)) ?? .bottom
        let spacing = StackSolver.length((properties["safeAreaSpacing"] as? Double)
            ?? (properties["safeAreaSpacing"] as? Int).map(Double.init) ?? StackLayout.defaultSpacing)
        var alignment = (horizontal: StackSolver.Alignment.center, vertical: StackSolver.Alignment.center)
        switch (edge, properties["safeAreaAlignment"] as? String) {
        case (.top, "leading"), (.bottom, "leading"): alignment.horizontal = .start
        case (.top, "trailing"), (.bottom, "trailing"): alignment.horizontal = .end
        case (.leading, "top"), (.trailing, "top"): alignment.vertical = .start
        case (.leading, "bottom"), (.trailing, "bottom"): alignment.vertical = .end
        default: break
        }
        guard marker.edge != edge || marker.spacing != spacing || marker.alignment != alignment else { return }
        marker.edge = edge
        marker.spacing = spacing
        marker.alignment = alignment
        if let parent = gtk_widget_get_parent(view.outerWidget) {
            gtk_widget_queue_resize(parent)
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
        for view in nodes {
            view.detach()
            if gtk_widget_get_parent(view.outerWidget) != nil {
                gtk_widget_unparent(view.outerWidget)
            }
        }
        background = nil
        overlay = nil
        inset = nil
    }
}
