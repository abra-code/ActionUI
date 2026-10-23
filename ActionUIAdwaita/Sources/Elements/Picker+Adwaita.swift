// Sources/Elements/Picker+Adwaita.swift
/*
 Picker on GTK: the title beside the choice, as macOS shows it (measured on macOS 27):
 - menu, wheel and no style: a GtkDropDown, as macOS's pop-up button (macOS has no wheel style and
   shows the menu);
 - segmented: an AdwToggleGroup, its segments equally wide, as macOS's segmented control;
 - radioGroup: a column of radio buttons (grouped GtkCheckButtons), the title beside the first; with
   horizontalRadioGroupLayout a row of them, 8 apart.
 labelsHidden hides the title; it still names the control for assistive technologies, as in
 SwiftUI. An empty title stays, 0 wide, so the control starts 8 after it, as for every control
 (measured on macOS 27); in a Form the title ends at the label column (FormLayout).

 - The options are the items. When the options have sections (a title, or a divider), the menu
   shows each titled section under its title and starts an untitled one with a line, as SwiftUI's
   Section does in a menu; a radio group does the same with headings (owner decision: SwiftUI draws
   the headers as radio rows); segments show the items alone.
 - The selected item is the one whose tag is the value, else the first option (Picker's initial
   value). A value that is no option's tag leaves the dropdown on the item it showed (GtkDropDown
   always keeps one selected, where macOS shows an empty pop-up button), and selects no segment and
   no radio button.
 - Choosing an item runs Core's Picker.userSelected (the value, then actionID with the tag as
   context); an update fires nothing.
*/

import CAdwaita

private let pickerStateKey = AttachKey<PickerState>("actionui-picker-state")

/// What the control shows, kept on the Picker's box: the sections it was built from, the tag of
/// each item, and for the menu each section's start, for the radio group its buttons.
@MainActor private final class PickerState {
    var sections: [Picker.Props.OptionSection]?
    var tags: [String] = []
    /// Each section's first item index and title, for the popup's headers.
    var sectionStarts: [(start: Int, title: String?)] = []
    /// The radio group's buttons, one per tag.
    var radios: [WidgetPointer] = []
}

extension Picker: ActionUIAdwaitaRenderer {
    /// The gap between the title and the control (SwiftUI's default spacing).
    static let titleSpacing: Int32 = 8
    /// No selection, GTK_INVALID_LIST_POSITION.
    static let noSelection = UInt32.max

    /// The widget each style needs (RenderNode.widgetKind).
    enum Kind: Int {
        case menu = 0, segmented, radioGroup
    }

    static func widgetKind(_ node: RenderNode) -> Int {
        switch Props(node.properties).style {
        case .segmented?: return Kind.segmented.rawValue
        case .radioGroup?: return Kind.radioGroup.rawValue
        case .menu?, .wheel?, nil: return Kind.menu.rawValue
        }
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, titleSpacing)!
        let state = PickerState()
        attach(state, to: box, key: pickerStateKey)
        // Left out of the accessibility tree: the control carries the title as its name.
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_box_append(typed(box), title)
        // A Form lines its title up with the other rows' (FormLayout).
        attach(LabeledRowMarker(.box), to: box, key: labeledRowMarkerKey)
        switch Kind(rawValue: node.widgetKind) ?? .menu {
        case .menu:
            let expression = gtk_property_expression_new(gtk_string_object_get_type(), nil, "string")
            let dropdown = gtk_drop_down_new(nil, expression)!
            // Its text is centered, though GTK reports no baseline for it (Baselines).
            attach(TextLineMarker(.centered), to: dropdown, key: textLineMarkerKey)
            gtk_box_append(typed(box), dropdown)
            connectUserSignal(dropdown, "notify::selected", .instanceAndArgument) { [weak node, weak state] in
                guard let node, let state else { return }
                let index = Int(gtk_drop_down_get_selected(OpaquePointer(dropdown)))
                guard index < state.tags.count else { return }
                userSelected(state.tags[index], node)
            }
        case .segmented:
            let group = adw_toggle_group_new()!
            adw_toggle_group_set_homogeneous(OpaquePointer(group), 1)
            gtk_widget_set_valign(group, GTK_ALIGN_CENTER)
            attach(TextLineMarker(.centered), to: group, key: textLineMarkerKey)
            gtk_box_append(typed(box), group)
            connectUserSignal(group, "notify::active-name", .instanceAndArgument) { [weak node] in
                guard let node, let name = swiftString(adw_toggle_group_get_active_name(OpaquePointer(group))) else { return }
                userSelected(name, node)
            }
        case .radioGroup:
            let column = newWidget(gtk_box_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_RADIO_GROUP)
            gtk_orientable_set_orientation(OpaquePointer(column), GTK_ORIENTATION_VERTICAL)
            // The title beside the first row, as macOS puts it (update centers it on the row's
            // height): GTK cannot line them up by baseline, since a check button reports none.
            gtk_widget_set_valign(column, GTK_ALIGN_START)
            gtk_widget_set_valign(title, GTK_ALIGN_START)
            gtk_box_append(typed(box), column)
        }
        return box
    }

    private static func userSelected(_ tag: String, _ node: RenderNode) {
        Picker.userSelected(tag, element: node.element, model: node.model, windowUUID: node.windowUUID, props: Props(node.properties))
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: pickerStateKey),
              let title = Gtk.Widget(widget).firstChild?.pointer else { return }
        let control = accessibleWidget(widget)
        let props = Props(node.properties)

        Gtk.Label(title).text = props.title
        Gtk.Widget(title).isVisible = !node.environment.labelsHidden

        let kind = Kind(rawValue: node.widgetKind) ?? .menu
        if state.sections != props.sections {
            state.sections = props.sections
            state.tags = props.sections.flatMap { $0.items.map(\.tag) }
            switch kind {
            case .menu: setOptions(OpaquePointer(control), props.sections, state)
            case .segmented: setSegments(control, props.sections)
            case .radioGroup: setRadios(control, props.sections, state, node)
            }
        }
        let value = node.model.value as? String ?? props.options.first?.tag
        let index = value.flatMap { state.tags.firstIndex(of: $0) }
        switch kind {
        case .menu:
            let dropdown = OpaquePointer(control)
            let selected = index.map(UInt32.init) ?? noSelection
            if gtk_drop_down_get_selected(dropdown) != selected {
                gtk_drop_down_set_selected(dropdown, selected)
            }
            clearLabelledBy(dropdown)
        case .segmented:
            let group = OpaquePointer(control)
            if index != nil, let value {
                if swiftString(adw_toggle_group_get_active_name(group)) != value {
                    adw_toggle_group_set_active_name(group, value)
                }
            } else if adw_toggle_group_get_active(group) != noSelection {
                adw_toggle_group_set_active(group, noSelection)
            }
        case .radioGroup:
            // horizontalRadioGroupLayout: the buttons in a row, 8 apart (measured on macOS 27).
            let orientation = props.horizontalRadioGroupLayout ? GTK_ORIENTATION_HORIZONTAL : GTK_ORIENTATION_VERTICAL
            if gtk_orientable_get_orientation(OpaquePointer(control)) != orientation {
                gtk_orientable_set_orientation(OpaquePointer(control), orientation)
                gtk_box_set_spacing(typed(control), props.horizontalRadioGroupLayout ? titleSpacing : 0)
            }
            for (position, radio) in state.radios.enumerated() {
                Gtk.CheckButton(radio).isActive = position == index
            }
            alignBesideFirstRow(title, control)
        }
    }

    /// The control, which assistive technologies read (the box only holds it and the title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        Gtk.Widget(widget).lastChild?.pointer ?? widget
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

    /// Moves `title` down by half of what the radio column's first row is taller than the title, so
    /// its text is on the row's line.
    private static func alignBesideFirstRow(_ title: WidgetPointer, _ column: WidgetPointer) {
        guard Gtk.Widget(title).isVisible, let first = Gtk.Widget(column).firstChild?.pointer else { return }
        let row = Int32(clamping: Gtk.Widget(first).measure(GTK_ORIENTATION_VERTICAL).natural)
        let label = Int32(clamping: Gtk.Widget(title).measure(GTK_ORIENTATION_VERTICAL).natural)
        let margin = max(0, (row - (label - gtk_widget_get_margin_top(title))) / 2)
        if gtk_widget_get_margin_top(title) != margin {
            gtk_widget_set_margin_top(title, margin)
        }
    }

    /// One segment per item, named by its tag (sections are not shown).
    private static func setSegments(_ group: WidgetPointer, _ sections: [Props.OptionSection]) {
        adw_toggle_group_remove_all(OpaquePointer(group))
        for item in sections.flatMap(\.items) {
            // A repeated tag gets one segment: a toggle group refuses two toggles of one name.
            guard adw_toggle_group_get_toggle_by_name(OpaquePointer(group), item.tag) == nil else { continue }
            let toggle = adw_toggle_new()!
            adw_toggle_set_label(toggle, item.title)
            adw_toggle_set_name(toggle, item.tag)
            // The group takes the toggle's reference.
            adw_toggle_group_add(OpaquePointer(group), toggle)
        }
    }

    /// One radio button per item, in one group, under each titled section's heading; an untitled
    /// section after the first starts with a line, as the menu's popup shows it.
    private static func setRadios(_ column: WidgetPointer, _ sections: [Props.OptionSection], _ state: PickerState, _ node: RenderNode) {
        while let child = Gtk.Widget(column).firstChild?.pointer {
            gtk_box_remove(typed(column), child)
        }
        state.radios = []
        for (position, section) in sections.enumerated() {
            if let title = section.title, !title.isEmpty {
                let heading = gtk_label_new(title)!
                gtk_label_set_xalign(opaque(heading), 0)
                Gtk.Widget(heading).setCSSClass("heading", true)
                gtk_box_append(typed(column), heading)
            } else if position > 0 {
                gtk_box_append(typed(column), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
            }
            for item in section.items {
                let radio = gtk_check_button_new_with_label(item.title)!
                if let first = state.radios.first {
                    gtk_check_button_set_group(typed(radio), typed(first))
                }
                let tag = item.tag
                connectUserSignal(radio, "toggled", .instanceOnly) { [weak node] in
                    guard let node, Gtk.CheckButton(radio).isActive else { return }
                    userSelected(tag, node)
                }
                gtk_box_append(typed(column), radio)
                state.radios.append(radio)
            }
        }
    }

    /// Gives the dropdown a model of the options: one string list per section, flattened, so
    /// the sections stay visible to the popup's header factory.
    private static func setOptions(_ dropdown: OpaquePointer, _ sections: [Props.OptionSection], _ state: PickerState) {
        state.sectionStarts = []
        let store = g_list_store_new(gtk_string_list_get_type())!
        var start = 0
        for section in sections {
            state.sectionStarts.append((start, section.title))
            let list = OwnedObject(adopting: gtk_string_list_new(nil)!)
            for item in section.items {
                gtk_string_list_append(list.opaquePointer, item.title)
            }
            g_list_store_append(store, list.pointer)
            start += section.items.count
        }
        // The flattened model takes the store (handed over, so not owned here); the dropdown takes
        // its own reference to the model.
        let model = OwnedObject(adopting: gtk_flatten_list_model_new(store)!)
        gtk_drop_down_set_model(dropdown, model.opaquePointer)
        let useSections = sections.count > 1 || sections.contains { $0.title != nil }
        if useSections {
            // The dropdown takes its own reference; named, as an unnamed owner may be released
            // before the call (Owned.swift).
            let factory = headerFactory(state)
            gtk_drop_down_set_header_factory(dropdown, factory.opaquePointer)
        } else {
            gtk_drop_down_set_header_factory(dropdown, nil)
        }
    }

    /// The popup's section headers: a titled section's title, a line before an untitled section
    /// that is not the first, nothing before an untitled first one.
    private static func headerFactory(_ state: PickerState) -> OwnedObject {
        let factory = OwnedObject(adopting: gtk_signal_list_item_factory_new()!)
        connectObjectSignal(factory.pointer, "setup") { header in
            gtk_list_header_set_child(OpaquePointer(header), gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        }
        connectObjectSignal(factory.pointer, "bind") { [weak state] header in
            guard let state, let box = gtk_list_header_get_child(OpaquePointer(header)) else { return }
            while let child = Gtk.Widget(box).firstChild?.pointer {
                gtk_box_remove(typed(box), child)
            }
            let start = Int(gtk_list_header_get_start(OpaquePointer(header)))
            guard let section = state.sectionStarts.last(where: { $0.start <= start }) else { return }
            if let title = section.title, !title.isEmpty {
                let label = gtk_label_new(title)!
                gtk_label_set_xalign(opaque(label), 0)
                Gtk.Widget(label).setCSSClass("heading", true)
                gtk_box_append(typed(box), label)
            } else if section.start > 0 {
                gtk_box_append(typed(box), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
            }
        }
        return factory
    }
}
