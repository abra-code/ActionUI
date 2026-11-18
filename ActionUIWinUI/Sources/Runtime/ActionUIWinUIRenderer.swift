// Sources/Runtime/ActionUIWinUIRenderer.swift
/*
 What a WinUI renderer of one element type provides, as on Linux (ActionUIAdwaitaRenderer). The
 renderer is retained-mode: each element instance gets its WinUI object once, and `update` then
 makes the object show the model whenever something it read changes (RenderNode.sync runs it
 under observation tracking).
*/

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
}
