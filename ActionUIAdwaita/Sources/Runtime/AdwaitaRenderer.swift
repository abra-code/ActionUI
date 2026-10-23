// Sources/Runtime/AdwaitaRenderer.swift
/*
 What a GTK renderer of one element type provides. The renderer is retained-mode: each element
 instance gets its widget once, and `update` then makes the widget show the model whenever
 something it read changes (RenderNode.sync runs it under observation tracking).
*/

import CAdwaita

/// How an element grows when offered more space than it needs (SwiftUI's flexibility).
struct Expansion: OptionSet {
    let rawValue: Int
    static let horizontal = Expansion(rawValue: 1)
    static let vertical = Expansion(rawValue: 2)
    static let both: Expansion = [.horizontal, .vertical]
}

@MainActor
protocol ActionUIAdwaitaRenderer {
    /// Creates the element's widget, once per element instance and widget kind. Reads nothing
    /// from the model; the kind to make is `node.widgetKind`, which the node set from widgetKind
    /// just before. What the widget shows is set by `update`, which runs right after.
    static func makeWidget(_ node: RenderNode) -> WidgetPointer

    /// Which kind of widget the element needs, for an element whose GTK widget type depends on
    /// the model (an Image shows a symbol in a GtkImage and a file in a GtkPicture). Read at the
    /// start of every sync; when it changes, the node replaces its widget with a new one from
    /// makeWidget. Default: 0, a single kind.
    static func widgetKind(_ node: RenderNode) -> Int

    /// Makes the widget show the model: properties, value, states, children. Runs after makeWidget
    /// and again whenever anything it read changed. Idempotent. Never writes the model and never
    /// fires actions. Sets a widget property only when it differs (setting an entry's text moves
    /// the cursor).
    static func update(_ widget: WidgetPointer, _ node: RenderNode)

    /// Expansion before frame modifiers. Default: none.
    static var defaultExpansion: Expansion { get }

    /// The widget assistive technologies read for the element, when it is not the element's
    /// widget itself but one inside it (a Picker's dropdown beside its title): ModifierBox writes
    /// the accessible label and hint there. Default: the widget.
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer

    /// The element's accessible name when the document gives no accessibilityLabel, as SwiftUI
    /// names a control after its title and a Text after its text. ModifierBox writes it after the
    /// renderer's update. Default: nil, the name GTK gives the widget itself.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String?

    /// The base modifiers the element's own box applies (ModifierBox.update), out of the ones the
    /// document gives it; its descendants inherit from all of them (Environment). Default: all.
    static func boxModifiers(_ modifiers: BaseModifiers) -> BaseModifiers

    /// The environment the element and its descendants see, from the one it inherits with its
    /// own base modifiers applied (a Form sets inForm). Default: that environment.
    static func environment(_ environment: Environment) -> Environment
}

extension ActionUIAdwaitaRenderer {
    static func widgetKind(_ node: RenderNode) -> Int { 0 }

    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer { widget }

    static func defaultAccessibleLabel(_ node: RenderNode) -> String? { nil }

    static var defaultExpansion: Expansion { [] }

    static func boxModifiers(_ modifiers: BaseModifiers) -> BaseModifiers { modifiers }

    static func environment(_ environment: Environment) -> Environment { environment }
}
