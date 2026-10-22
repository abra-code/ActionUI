// Sources/Elements/Picker+Adwaita.swift
/*
 Picker on GTK in its menu style: the title beside a GtkDropDown, as macOS shows a menu picker's
 label beside its pop-up button. labelsHidden hides the title; it still names the dropdown for
 assistive technologies, as in SwiftUI.

 - The options are the dropdown's items. When the options have sections (a title, or a divider),
   the popup shows each titled section under its title and starts an untitled one with a line,
   as SwiftUI's Section does in a menu.
 - The selected item is the one whose tag is the value, else the first option (Picker's initial
   value). A value that is no option's tag leaves the dropdown on the item it showed: GtkDropDown
   always keeps one selected, where macOS shows an empty pop-up button.
 - Choosing an item runs Core's Picker.userSelected (the value, then actionID with the tag as
   context); an update fires nothing.

 Not yet: the segmented, radioGroup and wheel styles show the dropdown (logged once).
*/

import CAdwaita

private let pickerStateKey = "actionui-picker-state"
@MainActor private var reportedStyles: Set<String> = []

/// What the dropdown shows, kept on the Picker's box: the sections its model was built from, and
/// the tag and section start of each item.
@MainActor private final class PickerState {
    var sections: [Picker.Props.OptionSection]?
    var tags: [String] = []
    /// Each section's first item index and title, for the popup's headers.
    var sectionStarts: [(start: Int, title: String?)] = []
}

extension Picker: ActionUIAdwaitaRenderer {
    /// The gap between the title and the dropdown (SwiftUI's default spacing).
    static let titleSpacing: Int32 = 8
    /// No selection, GTK_INVALID_LIST_POSITION.
    static let noSelection = UInt32.max

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, titleSpacing)!
        let state = PickerState()
        attach(state, to: box, key: pickerStateKey)
        let title = gtk_label_new(nil)!
        gtk_box_append(typed(box), title)
        let expression = gtk_property_expression_new(gtk_string_object_get_type(), nil, "string")
        let dropdown = gtk_drop_down_new(nil, expression)!
        gtk_box_append(typed(box), dropdown)
        connectUserSignal(dropdown, "notify::selected", .instanceAndArgument) { [weak node, weak state] in
            guard let node, let state else { return }
            let index = Int(gtk_drop_down_get_selected(OpaquePointer(dropdown)))
            guard index < state.tags.count else { return }
            Picker.userSelected(state.tags[index], element: node.element, model: node.model, windowUUID: node.windowUUID,
                                props: Props(node.properties))
        }
        return box
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(PickerState.self, on: widget, key: pickerStateKey),
              let title = gtk_widget_get_first_child(widget) else { return }
        let dropdown = OpaquePointer(accessibleWidget(widget))
        let props = Props(node.properties)

        if swiftString(gtk_label_get_text(opaque(title))) != props.title {
            gtk_label_set_text(opaque(title), props.title)
        }
        let showsTitle: gboolean = !props.title.isEmpty && !node.environment.labelsHidden ? 1 : 0
        if gtk_widget_get_visible(title) != showsTitle {
            gtk_widget_set_visible(title, showsTitle)
        }

        if state.sections != props.sections {
            setOptions(dropdown, props.sections, state)
        }
        let value = node.model.value as? String ?? props.options.first?.tag
        let selected = value.flatMap { state.tags.firstIndex(of: $0) }.map(UInt32.init) ?? noSelection
        if gtk_drop_down_get_selected(dropdown) != selected {
            gtk_drop_down_set_selected(dropdown, selected)
        }
        clearLabelledBy(dropdown)

        if let style = props.style, style != .menu, reportedStyles.insert(style.rawValue).inserted {
            ActionUIModel.shared.logger.log("Picker: the \(style.rawValue) style shows a dropdown on Linux for now", .warning)
        }
    }

    /// The dropdown, which assistive technologies read (the box only holds it and the title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        gtk_widget_get_last_child(widget) ?? widget
    }

    /// Named after its title, also when labelsHidden hides it, as in SwiftUI.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// Takes away the labelled-by relation GtkDropDown gives itself to the item it shows: it
    /// outranks the accessible label (the title, or accessibilityLabel), so the dropdown would be
    /// named after its selected item (measured over AT-SPI).
    static func clearLabelledBy(_ dropdown: OpaquePointer) {
        gtk_accessible_reset_relation(dropdown, GTK_ACCESSIBLE_RELATION_LABELLED_BY)
    }

    /// Gives the dropdown a model of the options: one string list per section, flattened, so
    /// the sections stay visible to the popup's header factory.
    private static func setOptions(_ dropdown: OpaquePointer, _ sections: [Props.OptionSection], _ state: PickerState) {
        state.sections = sections
        state.tags = sections.flatMap { $0.items.map(\.tag) }
        state.sectionStarts = []
        let store = g_list_store_new(gtk_string_list_get_type())!
        var start = 0
        for section in sections {
            state.sectionStarts.append((start, section.title))
            let list = gtk_string_list_new(nil)!
            for item in section.items {
                gtk_string_list_append(list, item.title)
            }
            g_list_store_append(store, UnsafeMutableRawPointer(list))
            g_object_unref(UnsafeMutableRawPointer(list))
            start += section.items.count
        }
        // The flattened model takes the store; the dropdown takes its own reference.
        let model = gtk_flatten_list_model_new(store)!
        gtk_drop_down_set_model(dropdown, model)
        g_object_unref(UnsafeMutableRawPointer(model))
        let useSections = sections.count > 1 || sections.contains { $0.title != nil }
        if useSections {
            // The dropdown takes its own reference.
            let factory = headerFactory(state)
            gtk_drop_down_set_header_factory(dropdown, factory)
            g_object_unref(UnsafeMutableRawPointer(factory))
        } else {
            gtk_drop_down_set_header_factory(dropdown, nil)
        }
    }

    /// The popup's section headers: a titled section's title, a line before an untitled section
    /// that is not the first, nothing before an untitled first one. The caller owns the factory.
    private static func headerFactory(_ state: PickerState) -> OpaquePointer {
        let factory = gtk_signal_list_item_factory_new()!
        connectObjectSignal(UnsafeMutableRawPointer(factory), "setup") { header in
            gtk_list_header_set_child(OpaquePointer(header), gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        }
        connectObjectSignal(UnsafeMutableRawPointer(factory), "bind") { [weak state] header in
            guard let state, let box = gtk_list_header_get_child(OpaquePointer(header)) else { return }
            while let child = gtk_widget_get_first_child(box) {
                gtk_box_remove(typed(box), child)
            }
            let start = Int(gtk_list_header_get_start(OpaquePointer(header)))
            guard let section = state.sectionStarts.last(where: { $0.start <= start }) else { return }
            if let title = section.title, !title.isEmpty {
                let label = gtk_label_new(title)!
                gtk_label_set_xalign(opaque(label), 0)
                gtk_widget_add_css_class(label, "heading")
                gtk_box_append(typed(box), label)
            } else if section.start > 0 {
                gtk_box_append(typed(box), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
            }
        }
        return factory
    }
}
