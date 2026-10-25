// Sources/Elements/FormattedTextField.swift
/*
 A TextField with a number format (integer, decimal, percent, currency): the entry shows the value
 as the user's locale writes it (NumberFormatting), and the value stays a String in the model, as
 on Apple ("12.0", "1234"). Measured on macOS 27 (SwiftUI's TextField(value:format:)):

 - Typing sets the value when the text starts with a number, at each change: "12abc" is 12. Text
   that does not ("abc", nothing) leaves the value as it was. An integer field drops the fraction
   ("0.999" is 0).
 - Return and leaving the field round the value to what the format shows (0.999 with two fraction
   digits is 1.0) and write it formatted again, which also undoes text that is no number.
 - Entering the field takes the value the text shows (a value of 1.239 shown as "1.24" becomes
   1.24), as SwiftUI's field reads its text when editing begins.
 - The program changing the value while the user edits replaces the text; writing the same number
   another way ("12" for "12.0") is no change, as the binding reads a number.

 Each change of the value runs valueChangeActionID, as the Apple binding does; actionID runs after
 the rounding, so its handler sees the value shown. The value is read as SwiftUI's binding reads it:
 Int(text) for an integer field, else Double(text), 0 when it is neither.
*/

import CAdwaita

/// The value (the model's String) a formatted field last showed or wrote: an update that finds
/// another value comes from the program and replaces the text, also while the user edits. And
/// whether the focus is in the field: a window that becomes active again emits "enter" on the
/// field that kept its focus, which is no new editing.
final class FormattedFieldState {
    var value: String?
    var editing = false
}

let formattedFieldStateKey = AttachKey<FormattedFieldState>("actionui-formatted-field")

@MainActor
enum FormattedTextField {
    /// The entry's text changed by the user's hand, or the focus entered it: the number at its
    /// start becomes the value.
    static func userChanged(_ entry: WidgetPointer, _ node: RenderNode, format: NumberFormatSpec) {
        let text = Gtk.Editable(entry).text
        guard let number = NumberFormatting.number(from: text, format: format), let value = modelString(number, format) else { return }
        state(entry).value = value
        TextField.userEditedText(value, element: node.element, model: node.model, windowUUID: node.windowUUID, props: TextField.Props(node.properties))
    }

    /// The focus entered the entry: the value its text shows becomes the value, unless the focus
    /// was in it already (its window becoming active again).
    static func focusEntered(_ entry: WidgetPointer, _ node: RenderNode, format: NumberFormatSpec) {
        let state = state(entry)
        guard !state.editing else { return }
        state.editing = true
        userChanged(entry, node, format: format)
    }

    /// The focus moved out of the entry (its window becoming inactive keeps it there).
    static func focusLeft(_ entry: WidgetPointer) {
        attached(on: UnsafeMutableRawPointer(entry), key: formattedFieldStateKey)?.editing = false
    }

    /// Return or the focus leaving: the value rounded to what is shown, written formatted again.
    static func commit(_ entry: WidgetPointer, _ node: RenderNode, format: NumberFormatSpec) {
        let props = TextField.Props(node.properties)
        let current = currentValue(node, props)
        let shown = NumberFormatting.string(number(of: current, format), format: format)
        let rounded = NumberFormatting.number(from: shown, format: format).flatMap { modelString($0, format) } ?? current
        state(entry).value = rounded
        TextField.userEditedText(rounded, element: node.element, model: node.model, windowUUID: node.windowUUID, props: props)
        let text = NumberFormatting.string(number(of: rounded, format), format: format)
        UpdateGuard.applying { Gtk.Editable(entry).text = text }
    }

    /// The renderer's update: the value formatted, unless the user is editing the value the field
    /// itself wrote.
    static func update(_ entry: WidgetPointer, _ node: RenderNode, format: NumberFormatSpec) {
        let value = currentValue(node, TextField.Props(node.properties))
        let state = state(entry)
        let focused = TextField.containsWindowFocus(entry)
        // The focus can leave inside an update (the field disabled), when "leave" runs no handler.
        if !focused { state.editing = false }
        let changed = state.value.map { number(of: $0, format) != number(of: value, format) } ?? true
        guard changed || !focused else { return }
        state.value = value
        Gtk.Editable(entry).text = NumberFormatting.string(number(of: value, format), format: format)
    }

    /// The model's value, else the initial one.
    private static func currentValue(_ node: RenderNode, _ props: TextField.Props) -> String {
        node.model.value as? String ?? props.initialValue
    }

    /// The value as the Apple binding reads it: Int(text) for an integer field, else Double(text);
    /// 0 when it is neither.
    static func number(of value: String, _ format: NumberFormatSpec) -> Double {
        if case .integer = format { return Int(value).map(Double.init) ?? 0 }
        return Double(value) ?? 0
    }

    /// The model's String for a number read from the text, as the Apple binding writes it: an
    /// integer field's without its fraction ("12"), else Double's ("12.0"); nil for an integer
    /// beyond Int.
    static func modelString(_ number: Double, _ format: NumberFormatSpec) -> String? {
        guard case .integer = format else { return String(number) }
        guard let integer = Int(exactly: number.rounded(.towardZero)) else { return nil }
        return String(integer)
    }

    private static func state(_ entry: WidgetPointer) -> FormattedFieldState {
        if let state = attached(on: UnsafeMutableRawPointer(entry), key: formattedFieldStateKey) { return state }
        let state = FormattedFieldState()
        attach(state, to: UnsafeMutableRawPointer(entry), key: formattedFieldStateKey)
        return state
    }
}
