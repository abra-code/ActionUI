// Sources/Runtime/AdwaitaElement.swift
/*
 What an add-on library implements for an element type on GTK, the counterpart of Apple's
 ActionUIViewConstruction: the element's spec (ActionUIElementSpec, shared with Apple) with the two
 calls that draw it. ActionUIRegistry.register(_:as:) binds it to a JSON type token, as on Apple.

 The built-in renderers' protocol (ActionUIAdwaitaRenderer) stays internal, so its layout hooks can
 change with the renderer; a registered element goes through the adapter below. Widgets cross this
 boundary as OpaquePointer, as they do from RichText and AsyncImageCache: each of those packages
 sees GTK through a clang module of its own, and a GtkWidget from one is a different Swift type from
 a GtkWidget from another.
*/

import CAdwaita

@MainActor
public protocol ActionUIAdwaitaElement: ActionUIElementSpec {
    /// Creates the element's widget (a `GtkWidget *`), once per element instance; the node takes its
    /// reference, floating or not. Reads nothing from the model: what it read would count as read by
    /// the parent, and `update` runs right after. How the element grows is the widget's own:
    /// gtk_widget_set_hexpand and gtk_widget_set_vexpand. A closure handed to GTK or kept by the
    /// element captures the node weakly: a node keeps its window's data alive while something holds
    /// it, and a strong capture on the widget's own signal is a cycle.
    static func makeWidget(_ node: RenderNode) -> OpaquePointer

    /// Makes the widget show the model. Runs after makeWidget and again whenever a value, state or
    /// property it read changes, or after `node.setNeedsUpdate()`. Idempotent. Never writes the
    /// model and never fires actions.
    static func update(_ widget: OpaquePointer, _ node: RenderNode)
}

/// A registered element in the built-in renderers' place.
private enum AddOnRenderer<Element: ActionUIAdwaitaElement>: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        typed(Element.makeWidget(node))
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        Element.update(opaque(widget), node)
    }
}

extension ActionUIRegistry {
    /// Registers an add-on's element type, so its `type` token can be used in ActionUI JSON exactly
    /// like a built-in element. An add-on exposes a small `register()` that the host calls at launch,
    /// before any window that uses the element is built. A later call for the same token replaces
    /// the earlier type for the elements built after it; those already shown keep theirs.
    ///
    /// - Parameters:
    ///   - type: a type conforming to ``ActionUIAdwaitaElement``.
    ///   - typeName: the JSON `type` token to bind. Defaults to the Swift type's own name.
    public func register(_ type: any ActionUIAdwaitaElement.Type, as typeName: String? = nil) {
        let key = typeName ?? String(describing: type)
        specs[key] = type
        renderers[key] = adapter(for: type)
        logger.log("Registered custom view type: \(key)", .verbose)
    }

    private func adapter<Element: ActionUIAdwaitaElement>(for type: Element.Type) -> any ActionUIAdwaitaRenderer.Type {
        AddOnRenderer<Element>.self
    }
}
