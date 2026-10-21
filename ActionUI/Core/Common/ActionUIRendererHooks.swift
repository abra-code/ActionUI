// Core/Common/ActionUIRendererHooks.swift
/*
 The few places where portable model code needs its renderer to take part in a change. Core sets a
 plain default; a renderer installs its own when it loads its built-in elements (SwiftUI:
 ActionUIRegistry.loadRendererBuiltIns in Common/ActionUIRegistry+SwiftUI.swift).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
enum ActionUIRendererHooks {
    /// Runs a structural mutation (an element inserted or removed). `animated` is true when the
    /// element declares a `transition`, so a renderer can play it; the default applies the change
    /// at once.
    static var structuralMutation: (_ animated: Bool, _ body: () -> Void) -> Void = { _, body in body() }

    /// Markdown text as the AttributedString a Text element starts with. The default keeps the text
    /// as it is: FoundationEssentials has no Markdown parser.
    static var markdown: (String) -> AttributedString = { AttributedString($0) }

    /// A color value as the text getElementValueAsString gives: hex. The default writes an `.rgba`
    /// color and nothing for a named one, whose components only a renderer knows.
    static var colorHex: (ColorSpec) -> String? = { $0.hexText }

    /// A value a host passes to setElementValue, made into one the model stores: a renderer's own
    /// color type into a ColorSpec, say. The default keeps the value.
    static var hostValue: (Any) -> Any = { $0 }
}
