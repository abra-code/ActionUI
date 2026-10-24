// Sources/Elements/Group+Adwaita.swift
/*
 Group on GTK: its children laid out as its parent stack's own, as SwiftUI's Group has no layout
 of its own. Measured on macOS 27 (layout parity fixtures): a Group's modifiers apply to each child,
 not to the Group as a whole, so a Group padded 10 pads each child 10 and a Group framed 50 x 30
 puts each child in a 50 x 30 frame.

 - Each child's box sits in a child box of the Group's (a ModifierBox), which takes the Group's
   padding, frame, paint, shadow, effects, opacity and hidden. The Group's own box takes none of
   them (boxModifiers) but hidden, which also takes the Group's widget, and with it the children,
   out of the accessibility tree. Its children inherit the rest (font, foregroundStyle, disabled)
   through the Environment, as from any parent.
 - In a stack or a ZStack (a widget with a StackConfiguration or a ZStackConfiguration), the
   stack lays the child boxes out among its own children (stackChildren), with its spacing,
   Spacers and alignment. The Group's box and widget span the stack from its origin, so the child
   boxes are placed in the stack's coordinates; they measure 0 and contain no point of their own
   (passesPicks), so a click or hover beside the Group's children reaches the stack or a sibling
   before the Group, as SwiftUI's Group has no area of its own.
 - In an HSplitView or VSplitView each child box is a pane of its own, as on macOS (SplitLayout).
 - Elsewhere (a window's root, inside another Group's child box) the Group lays its children out
   as a VStack with no spacing. A Group in a Group is not laid out as the outer stack's children.
 - The template form shows no rows yet, as on GroupBox.
*/

import CAdwaita

/// Attached to a Group's widget.
@MainActor
final class GroupMarker {}

let groupMarkerKey = AttachKey<GroupMarker>("actionui-group")

/// Attached to the box a Group puts around each of its children.
@MainActor
final class GroupChildBoxMarker {}

let groupChildBoxMarkerKey = AttachKey<GroupChildBoxMarker>("actionui-group-child-box")

@MainActor private var reportedTemplate = false

extension Group: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = StackLayout.makeStack(axis: .vertical)
        attach(GroupMarker(), to: widget, key: groupMarkerKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        syncChildBoxes(widget, node, after: nil)
        if !reportedTemplate, node.effectiveElement.subviews?["template"] != nil {
            reportedTemplate = true
            ActionUIModel.shared.logger.log("Group: the template form shows no rows on Linux yet", .warning)
        }
    }

    /// Puts the boxes of `node`'s children in child boxes of `widget`, in order after `first` (a
    /// Section's header box; nil: from the start), and applies the element's box modifiers to each
    /// (Section shares it).
    static func syncChildBoxes(_ widget: WidgetPointer, _ node: RenderNode, after first: WidgetPointer?) {
        let modifiers = BaseModifiers(node.properties)
        var previous = first
        node.syncChildren(node.subviews("children"), insert: { child, _ in
            let box = childBox(of: child, in: widget) ?? makeChildBox(child)
            // Already in place: nothing to do (gtk_widget_insert_after would still relayout).
            if gtk_widget_get_parent(box) != widget || gtk_widget_get_prev_sibling(box) != previous {
                gtk_widget_insert_after(box, widget, previous)
            }
            previous = box
            ModifierBox.applyBoxModifiers(box, modifiers)
        }, remove: { child in
            let box = childBox(of: child, in: widget)
            gtk_widget_unparent(child.outerWidget)
            if let box {
                gtk_widget_unparent(box)
            }
        })
    }

    /// The Group's own box applies none of what its child boxes do, except hidden: on the Group's
    /// widget it hides the children from assistive technologies too (ModifierBox.update), as
    /// SwiftUI's hidden does.
    static func boxModifiers(_ modifiers: BaseModifiers) -> BaseModifiers {
        var own = modifiers
        own.padding = nil
        own.frame = nil
        own.background = nil
        own.cornerRadius = nil
        own.clipShape = nil
        own.border = nil
        own.shadow = nil
        own.offset = nil
        own.rotationDegrees = nil
        own.scale = nil
        own.opacity = nil
        return own
    }

    // MARK: Layout

    /// The Group's widget inside `box`, when `box` is a Group's box (the stacks lay out its
    /// children as their own).
    static func widget(inBox box: WidgetPointer) -> WidgetPointer? {
        guard attached(on: box, key: boxLayoutKey) != nil,
              let content = ModifierBox.content(of: box),
              let element = Gtk.Widget(content).firstChild?.pointer,
              attached(on: element, key: groupMarkerKey) != nil else { return nil }
        return element
    }

    /// True when `widget` is a Group's widget whose children a stack, a ZStack or a split view lays
    /// out: the container of its box is one.
    static func isFlattened(_ widget: WidgetPointer) -> Bool {
        guard attached(on: widget, key: groupMarkerKey) != nil,
              let content = gtk_widget_get_parent(widget),
              let box = gtk_widget_get_parent(content),
              let container = gtk_widget_get_parent(box) else { return false }
        return attached(on: container, key: stackConfigurationKey) != nil
            || attached(on: container, key: zStackConfigurationKey) != nil
            || attached(on: container, key: splitStateKey) != nil
    }

    /// True for the widgets of a Group whose children a stack lays out, which span the stack: its
    /// box, its content group and its own widget. Their `contains` says no to every point
    /// (ContainerWidget, ModifierBox), so gtk_widget_pick passes through them to the stack or to
    /// a sibling before the Group, instead of stopping at the Group over the empty space and over
    /// every sibling that comes before it; the child boxes keep their own area.
    static func passesPicks(_ widget: WidgetPointer) -> Bool {
        if attached(on: widget, key: groupMarkerKey) != nil {
            return isFlattened(widget)
        }
        if attached(on: widget, key: boxLayoutKey) != nil {
            guard let group = self.widget(inBox: widget) else { return false }
            return isFlattened(group)
        }
        // A content group: the element's widget is its only child.
        guard let element = Gtk.Widget(widget).firstChild?.pointer,
              attached(on: element, key: groupMarkerKey) != nil else { return false }
        return isFlattened(element)
    }

    /// False for a Group's child box around an element that takes no place (an EmptyView, whose
    /// box is not laid out): a stack gives it no place and no spacing either.
    static func takesPlace(_ box: WidgetPointer) -> Bool {
        guard attached(on: box, key: groupChildBoxMarkerKey) != nil,
              let content = ModifierBox.content(of: box),
              let element = Gtk.Widget(content).firstChild?.pointer else { return true }
        return gtk_widget_should_layout(element) != 0
    }

    /// Gives the boxes of the Groups among `container`'s children the whole container, from its
    /// origin, before the container places their children. Measured first, as GTK expects of an
    /// allocated widget; the box measures 0 (StackLayout.measure), so no width is needed.
    static func allocateGroups(in container: WidgetPointer, width: Int, height: Int) {
        for child in layoutChildren(container) where widget(inBox: child) != nil {
            _ = Gtk.Widget(child).measure(GTK_ORIENTATION_HORIZONTAL)
            _ = Gtk.Widget(child).measure(GTK_ORIENTATION_VERTICAL)
            gtk_widget_allocate(child, Int32(clamping: width), Int32(clamping: height), -1, nil)
        }
    }

    /// The child box around `child`'s box, when it is in `widget`.
    private static func childBox(of child: RenderNode, in widget: WidgetPointer) -> WidgetPointer? {
        guard let content = gtk_widget_get_parent(child.outerWidget),
              let box = gtk_widget_get_parent(content),
              gtk_widget_get_parent(box) == widget,
              attached(on: box, key: groupChildBoxMarkerKey) != nil else { return nil }
        return box
    }

    private static func makeChildBox(_ child: RenderNode) -> WidgetPointer {
        let box = ModifierBox.wrap(child.outerWidget)
        attach(GroupChildBoxMarker(), to: box, key: groupChildBoxMarkerKey)
        return box
    }
}

/// A stack's or ZStack's children as its layout places them (layoutChildren), with each Group
/// among them replaced by its child boxes, as SwiftUI lays a Group's children out as the stack's
/// own. A child box around an element that takes no place is left out.
@MainActor func stackChildren(_ widget: WidgetPointer) -> [WidgetPointer] {
    var children: [WidgetPointer] = []
    for child in layoutChildren(widget) {
        if let group = Group.widget(inBox: child) {
            children += layoutChildren(group).filter(Group.takesPlace)
        } else if Group.takesPlace(child) {
            children.append(child)
        }
    }
    return children
}
