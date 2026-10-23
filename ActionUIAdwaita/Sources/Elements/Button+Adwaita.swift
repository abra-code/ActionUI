// Sources/Elements/Button+Adwaita.swift
/*
 Button on GTK: a GtkButton whose content follows the properties as SwiftUI's label does: the title
 alone as text; an image alone (assetImage, else systemImage) as an icon; both side by side in an
 AdwButtonContent. A click runs Core's Button.userTapped (popover, sheet, cover, actionID), as a tap
 does on Apple; the widget changes an update makes fire nothing.

 - The icon is the one Image shows for the same name (SymbolNames, or an icon theme name for
   assetImage). imageScale sizes it as Image does (0.9, 1.1 or 1.4 em); without one it is GNOME's
   16 px.
 - Its accessible name is accessibilityLabel when set, else the title: GTK names a button from its
   content once the renderer takes away the relation to its label, which would outrank the label.
 - role destructive is libadwaita's destructive-action, a red button; cancel looks like any other
   button, as on macOS.
 - The inherited buttonStyle: bordered (and the platform default) is GTK's raised button;
   borderedProminent is suggested-action, filled with the accent color (destructive-action with the
   destructive role); borderless is a flat button; plain is a flat button without padding, minimum
   size or hover background, as large as its content, as SwiftUI's plain button is.
*/

import CAdwaita

extension Button: ActionUIAdwaitaRenderer {
    /// The style classes this renderer adds and removes.
    static let styleClasses = ["flat", "suggested-action", "destructive-action"]

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let button = gtk_button_new()!
        connectUserSignal(button, "clicked", .instanceOnly) { [weak node] in
            guard let node else { return }
            Button.userTapped(element: node.effectiveElement, model: node.model, windowUUID: node.windowUUID,
                              props: Props(node.properties))
        }
        // AdwButtonContent makes the button its label's mnemonic widget when it is rooted, after
        // the first update, which sets the relation again.
        connectSignal(button, "map", .instanceOnly) {
            clearLabelledBy(button)
        }
        return button
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let button: UnsafeMutablePointer<GtkButton> = typed(widget)
        let icon = iconName(props)
        switch (props.title.isEmpty, icon) {
        case (_, nil):
            if swiftString(gtk_button_get_label(button)) != props.title {
                gtk_button_set_label(button, props.title)
            }
        case (true, let icon?):
            if swiftString(gtk_button_get_icon_name(button)) != icon {
                gtk_button_set_icon_name(button, icon)
            }
        case (false, let icon?):
            let content: OpaquePointer
            if let child = gtk_button_get_child(button),
               g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(child)), adw_button_content_get_type()) != 0 {
                content = OpaquePointer(child)
            } else {
                content = OpaquePointer(adw_button_content_new()!)
                gtk_button_set_child(button, typed(content))
            }
            if swiftString(adw_button_content_get_icon_name(content)) != icon {
                adw_button_content_set_icon_name(content, icon)
            }
            if swiftString(adw_button_content_get_label(content)) != props.title {
                adw_button_content_set_label(content, props.title)
            }
        }
        clearLabelledBy(widget)
        let iconSize = props.imageScale.map { ["-gtk-icon-size: \(Image.iconSize(imageScale($0)))em;"] } ?? []
        StyleSheet.shared.apply(iconSize, to: widget, slot: "iconSize")
        applyStyle(widget, node.environment.buttonStyle, role: props.role)
    }

    /// Takes away the labelled-by relation GTK gives a button to its label (gtk_button_set_label,
    /// and AdwButtonContent's label as mnemonic): it outranks the accessible label that
    /// accessibilityLabel sets, and once a title gives way to an icon it names the button after the
    /// label that went (measured: an empty name). Without it GTK names a button from its content,
    /// the same title.
    static func clearLabelledBy(_ widget: WidgetPointer) {
        gtk_accessible_reset_relation(OpaquePointer(widget), GTK_ACCESSIBLE_RELATION_LABELLED_BY)
    }

    /// The icon of the button's image, nil when it has none: assetImage, else systemImage, when
    /// not empty.
    static func iconName(_ props: Props) -> String? {
        if let asset = props.assetImage, !asset.isEmpty {
            return Image.iconName(.themeIcon(asset))
        }
        if let symbol = props.systemImage, !symbol.isEmpty {
            return Image.iconName(.symbol(symbol))
        }
        return nil
    }

    private static func imageScale(_ scale: Props.ImageScale) -> Image.Props.ImageScale {
        switch scale {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }

    /// libadwaita's style classes for the style and role, and plain's own CSS.
    private static func applyStyle(_ widget: WidgetPointer, _ style: BaseModifiers.ButtonStyleName?, role: Props.Role?) {
        var classes: Set<String> = []
        switch style {
        case .plain?, .borderless?:
            classes.insert("flat")
        case .borderedProminent?:
            classes.insert(role == .destructive ? "destructive-action" : "suggested-action")
        case .bordered?, .automatic?, nil:
            break
        }
        if role == .destructive {
            classes.insert("destructive-action")
        }
        for name in styleClasses {
            Gtk.Widget(widget).setCSSClass(name, classes.contains(name))
        }
        let plain = style == .plain ? ["padding: 0;", "min-width: 0;", "min-height: 0;", "background: none;"] : []
        StyleSheet.shared.apply(plain, to: widget, slot: "plain")
    }
}
