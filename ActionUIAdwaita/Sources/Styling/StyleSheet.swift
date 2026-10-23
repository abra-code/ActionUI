// Sources/Styling/StyleSheet.swift
/*
 One stylesheet for every element's look. GTK 4.10 deprecated style providers on single widgets,
 so each distinct set of CSS declarations becomes one generated class (aui-1, aui-2, ...) added
 for the display; elements that look the same share the class.

 A widget's classes are kept per slot ("background", "font", ...): applying a slot again replaces
 that slot's classes, so a property change swaps a class instead of adding one. A slot can also
 hold named classes, such as libadwaita's "title-1" or "card". The order between generated
 classes is not defined, so two slots never set the same property on one widget.

 The sheet stays small and cheap to change, also while a color is dragged through
 setElementValue (one new look per frame):
 - Each generated class counts the widget slots that use it; when the last one lets it go (a
   slot replaced, a widget finalized), its rule is dropped.
 - The rules are spread over providers of at most rulesPerProvider rules, and a change reloads
   only its own provider. GTK parses a whole provider on every load, in time that grows faster
   than its length (measured: 1000 rules 11.5 ms, 4000 rules 140 ms), so one big provider made
   every new look slower than the last.
*/

import CAdwaita

/// A widget's classes, by slot; attached to the widget. Finalizing the widget releases them.
@MainActor
final class StyleSlots {
    var classes: [String: [String]] = [:]

    isolated deinit {
        for name in classes.values.joined() {
            StyleSheet.shared.release(name)
        }
    }
}

let styleSlotsKey = AttachKey<StyleSlots>("actionui-style")

@MainActor
final class StyleSheet {
    static let shared = StyleSheet()

    /// The most rules one provider holds.
    static let rulesPerProvider = 64

    private struct Rule {
        let body: String
        let group: Int
        var users = 0
    }

    private struct Group {
        let provider: OpaquePointer
        var names: [String] = []
        /// Added for the display; a group made before there was one is added on its next load.
        var installed = false
    }

    private var nameForBody: [String: String] = [:]
    private var rules: [String: Rule] = [:]
    private var groups: [Group] = []
    private var nextNumber = 1

    /// The generated class for these CSS declarations ("color: red;"), adding its rule the first
    /// time; nil for none. A rule no widget slot uses is dropped once one has used it.
    func className(for declarations: [String]) -> String? {
        guard !declarations.isEmpty else { return nil }
        let body = declarations.joined(separator: " ")
        if let existing = nameForBody[body] {
            return existing
        }
        let name = "aui-\(nextNumber)"
        nextNumber += 1
        let group = groupWithRoom()
        nameForBody[body] = name
        rules[name] = Rule(body: body, group: group)
        groups[group].names.append(name)
        reload(group)
        return name
    }

    /// Gives `widget` the classes for `declarations` and `named` in `slot`, in place of the
    /// slot's previous ones.
    func apply(_ declarations: [String], named: [String] = [], to widget: WidgetPointer, slot: String) {
        var wanted = named
        if let generated = className(for: declarations) {
            wanted.append(generated)
        }
        let slots: StyleSlots
        if let existing = attached(on: widget, key: styleSlotsKey) {
            slots = existing
        } else {
            slots = StyleSlots()
            attach(slots, to: widget, key: styleSlotsKey)
        }
        let previous = slots.classes[slot] ?? []
        guard previous != wanted else { return }
        slots.classes[slot] = wanted
        // A class another slot also holds (the same declarations in two slots) stays.
        let kept = Set(slots.classes.values.joined())
        for name in previous where !kept.contains(name) {
            Gtk.Widget(widget).setCSSClass(name, false)
        }
        for name in wanted {
            Gtk.Widget(widget).setCSSClass(name, true)
        }
        // Counted before releasing, so a class in both never drops to no users.
        for name in wanted {
            retain(name)
        }
        for name in previous {
            release(name)
        }
    }

    /// The CSS rules in use (for tests).
    var css: String {
        groups.flatMap { $0.names }.compactMap { name in rules[name].map { ".\(name) { \($0.body) }" } }
            .joined(separator: "\n")
    }

    /// The number of generated rules kept (for tests).
    var ruleCount: Int { rules.count }

    // MARK: Use counts

    private func retain(_ name: String) {
        rules[name]?.users += 1
    }

    /// One slot no longer uses `name`; its rule goes when nothing does.
    fileprivate func release(_ name: String) {
        guard var rule = rules[name] else { return }
        rule.users -= 1
        guard rule.users <= 0 else {
            rules[name] = rule
            return
        }
        rules[name] = nil
        nameForBody[rule.body] = nil
        groups[rule.group].names.removeAll { $0 == name }
        reload(rule.group)
    }

    // MARK: Fixed rules

    private var fixedProviders: [String: OpaquePointer] = [:]

    /// Loads `css` once under `name`, for structure a generated class cannot express (the buttons
    /// of a ControlGroup joined across the boxes their elements sit in). Calling it again with the
    /// same name does nothing.
    func installFixedRules(_ name: String, _ css: String) {
        guard fixedProviders[name] == nil, let display = gdk_display_get_default() else { return }
        let provider = gtk_css_provider_new()!
        gtk_css_provider_load_from_string(provider, css)
        gtk_style_context_add_provider_for_display(display, opaque(provider), guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
        fixedProviders[name] = opaque(provider)
    }

    // MARK: Providers

    /// A provider with room for one more rule, added for the display when new.
    private func groupWithRoom() -> Int {
        if let index = groups.firstIndex(where: { $0.names.count < Self.rulesPerProvider }) {
            return index
        }
        let provider = gtk_css_provider_new()!
        groups.append(Group(provider: opaque(provider)))
        return groups.count - 1
    }

    private func reload(_ group: Int) {
        if !groups[group].installed, let display = gdk_display_get_default() {
            gtk_style_context_add_provider_for_display(display, groups[group].provider,
                                                       guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
            groups[group].installed = true
        }
        let text = groups[group].names.compactMap { name in rules[name].map { ".\(name) { \($0.body) }" } }
            .joined(separator: "\n")
        gtk_css_provider_load_from_string(typed(groups[group].provider), text)
    }
}
