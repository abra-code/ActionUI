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
    /// Creates the element's widget, once per element instance. Reads nothing from the model:
    /// what the widget shows is set by `update`, which runs right after.
    static func makeWidget(_ node: RenderNode) -> WidgetPointer

    /// Makes the widget show the model: properties, value, states, children. Runs after makeWidget
    /// and again whenever anything it read changed. Idempotent. Never writes the model and never
    /// fires actions. Sets a widget property only when it differs (setting an entry's text moves
    /// the cursor).
    static func update(_ widget: WidgetPointer, _ node: RenderNode)

    /// Expansion before frame modifiers. Default: none.
    static var defaultExpansion: Expansion { get }
}

extension ActionUIAdwaitaRenderer {
    static var defaultExpansion: Expansion { [] }
}
