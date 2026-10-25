// Sources/Elements/ControlGroup+Adwaita.swift
/*
 ControlGroup on GTK: its children side by side with no gap, their buttons joined into one bar as
 GTK's "linked" style joins them, as macOS joins a control group's buttons into one bar with thin
 separators. As large as its children (measured on macOS 27: it does not grow in either axis; two
 buttons are 98 x 24 points).

 - libadwaita's linked rules join only buttons that are direct children of the linked box, and
   each element sits in its ModifierBox; fixed rules (StyleSheet.installFixedRules) apply the same
   corners and 1-pixel overlap to the buttons inside the boxes: a Button, a toggle button, and a
   menubutton or dropdown that is an element's own widget.
 - The title is not shown, as macOS shows none for a control group outside a menu or toolbar.
 - A child's padding and frame are left out (childBoxModifiers): macOS draws the group from its
   buttons' titles and ignores both (measured: three buttons with padding are 198 x 24 points, as
   without; a button framed 100 wide keeps its own width), so padded buttons stay joined.

 Not yet: a Picker, ColorPicker or Stepper stays apart from the bar (each is a box holding its title
 and its control); macOS joins them into it, a Picker as segments for its title and its menu.
 Right-to-left order; a title for assistive technologies (macOS reads the buttons).
*/

import CAdwaita

extension ControlGroup: ActionUIAdwaitaRenderer {
    /// The class the fixed rules match.
    static let linkedClass = "actionui-linked"

    /// libadwaita's linked corners and overlap, one level deeper: the container's children are
    /// element boxes, each holding its widget in a content group.
    static let linkedRules = """
        .\(linkedClass) > actionui-box:not(:first-child) > actionui-content > button,
        .\(linkedClass) > actionui-box:not(:first-child) > actionui-content > menubutton > button,
        .\(linkedClass) > actionui-box:not(:first-child) > actionui-content > dropdown > button {
            border-top-left-radius: 0; border-bottom-left-radius: 0; margin-left: -1px; }
        .\(linkedClass) > actionui-box:not(:last-child) > actionui-content > button,
        .\(linkedClass) > actionui-box:not(:last-child) > actionui-content > menubutton > button,
        .\(linkedClass) > actionui-box:not(:last-child) > actionui-content > dropdown > button {
            border-top-right-radius: 0; border-bottom-right-radius: 0; }
        """

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StyleSheet.shared.installFixedRules(linkedClass, linkedRules)
        let stack = StackLayout.makeStack(axis: .horizontal)
        Gtk.Widget(stack).setCSSClass(linkedClass, true)
        return stack
    }

    /// A child's padding and frame do not apply, as on macOS.
    static func childBoxModifiers(_ modifiers: BaseModifiers) -> BaseModifiers {
        var applied = modifiers
        applied.padding = nil
        applied.frame = nil
        return applied
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        StackLayout.configure(widget, spacing: 0, alignment: .center)
        syncContainerChildren(node, widget, node.subviews("children"))
    }
}
