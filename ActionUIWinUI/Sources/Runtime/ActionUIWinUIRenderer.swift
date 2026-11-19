// Sources/Runtime/ActionUIWinUIRenderer.swift
/*
 What a WinUI renderer of one element type provides, as on Linux (ActionUIAdwaitaRenderer). The
 renderer is retained-mode: each element instance gets its WinUI object once, and `update` then
 makes the object show the model whenever something it read changes (RenderNode.sync runs it
 under observation tracking).
*/

/// How an element grows when offered more space than it needs (SwiftUI's flexibility), as on Linux.
struct Expansion: OptionSet {
    let rawValue: Int
    static let horizontal = Expansion(rawValue: 1)
    static let vertical = Expansion(rawValue: 2)
    static let both: Expansion = [.horizontal, .vertical]
}

@MainActor
protocol ActionUIWinUIRenderer {
    /// Creates the element's WinUI object, once per element instance. Reads nothing from the
    /// model: what it read would count as read by the parent, and `update` runs right after.
    /// Throws when the shim could not create it; the node then shows a placeholder.
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject

    /// Makes the object show the model: properties, value, children. Runs after makeView and
    /// again whenever anything it read changed. Idempotent. Never writes the model and never fires
    /// actions.
    static func update(_ view: WinUIObject, _ node: RenderNode)

    /// How the element grows in a stack, before frame modifiers: a TextField takes the width it
    /// is offered. Default: none, it keeps the size it asks for.
    static var defaultExpansion: Expansion { get }

    /// The same for one element, when it depends on its properties (a ScrollView expands along its
    /// scroll axes). Read during the node's sync, tracked, and once at its creation, untracked.
    /// Default: defaultExpansion.
    static func expansion(_ node: RenderNode) -> Expansion

    /// The axes along which a stack can make the element smaller than it asks for, as SwiftUI
    /// shares a stack's room: a Text across a row (it wraps), a ScrollView along its scroll axes, a
    /// stack along the axes its children can be made smaller in. Read as `expansion` is. Default:
    /// none.
    static func compression(_ node: RenderNode) -> Expansion
}

extension ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { [] }

    static func expansion(_ node: RenderNode) -> Expansion { defaultExpansion }

    static func compression(_ node: RenderNode) -> Expansion { [] }
}
