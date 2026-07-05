// Add-ons/ActionUIRichText/Sources/RichText.swift
/*
 Sample JSON for RichText:
 {
   "type": "RichText",
   "id": 1,                  // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "markdown": "# Title\n\nA **bold** word, a `code` span, and a [link](https://example.com).",
                                             // Optional: Markdown source to render; seeds the element value.
                                             //           "" or nil renders an empty document.
     "baseFontSize": 15,                     // Optional: Number; base font point size. Omit for Dynamic Type body.
     "syntaxHighlighting": true              // Optional: Bool; color fenced code blocks by language. Default from
                                             //           the RichText theme.
   }
   // Note: baseline View properties (padding, hidden, background, frame, opacity, cornerRadius, actionID,
   // onAppearActionID, onDisappearActionID, etc.) are inherited from base View. The document is read-only but
   // selectable, self-sizes to its content for the proposed width, and handles its own links (via RichText's
   // URL policy: http/https/mailto/tel only).
 }

 A rich-text DISPLAY element backed by the RichText package, implemented as an ActionUI add-on
 (registered via ActionUIRichText.register()):
   macOS / iOS / visionOS - RichText.RichText (a SwiftUI View; RichText's platforms).
 A whole Markdown document (headings, code blocks, quotes, lists, GFM tables, inline styling, links) is
 laid out into ONE native text view, so the entire document is selectable and copyable as a single unit
 (copy is table-aware: RTF / HTML / Markdown).

 Observable state (via getElementValue / setElementValue):
   value (String)   Current Markdown source. Write new Markdown to re-render; "" or nil renders empty.

 Implementation note: the RichText PACKAGE is a module named `RichText` and its view is also `RichText`.
 `import RichText` brings the view TYPE `RichText` into scope unqualified, which shadows the module name -
 so `RichText.RichText` does not work (it reads as a member of the type). The wrapped view is therefore
 constructed as plain `RichText(...)`. And if THIS element type were also named `RichText`, that same-module
 type would win over the imported one, hiding the view entirely; so the element type is named
 `RichTextView` and registered under the JSON token "RichText" via register(_:as:). The type and its
 witnesses are internal to this module - an internal type conforming to a public protocol keeps internal
 witnesses; only ActionUIRichText.register() is public.
 */

import SwiftUI
import ActionUI
import RichText

struct RichTextView: ActionUIViewConstruction {

    // The element's runtime value is the Markdown source string (value-primary, like the core
    // AsyncImage element and the ActionUICachedImage add-on).
    static var valueType: Any.Type = String.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        if let markdown = validated["markdown"], !(markdown is String) {
            logger.log("RichText markdown must be a String; ignoring", .warning)
            validated["markdown"] = nil
        }

        if let fontSize = validated["baseFontSize"], numericCGFloat(fontSize) == nil {
            logger.log("RichText baseFontSize must be a number; ignoring", .warning)
            validated["baseFontSize"] = nil
        }

        if let highlighting = validated["syntaxHighlighting"], !(highlighting is Bool) {
            logger.log("RichText syntaxHighlighting must be a Bool; ignoring", .warning)
            validated["syntaxHighlighting"] = nil
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // Effective source: the runtime value (setElementValue) wins, else the "markdown" JSON property.
        // buildView receives the validated `properties` directly, whereas initialValue cannot read the
        // "markdown" seed (model.validatedProperties is internal to ActionUI), so the seed is resolved
        // here - the same split the ActionUIQuickLook / ActionUICachedImage add-ons use for their seeds.
        let runtime = (model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let markdown = runtime ?? (properties["markdown"] as? String) ?? ""

        // Start from the package's default theme and override only the knobs that were provided, so
        // untouched theme values keep their defaults.
        var theme = RichTextTheme.default
        if let fontSize = numericCGFloat(properties["baseFontSize"]) { theme.baseFontSize = fontSize }
        if let highlighting = properties["syntaxHighlighting"] as? Bool { theme.syntaxHighlighting = highlighting }

        // The TextKit substrate is deliberately NOT exposed: this uses RichText's default (TextKit 1),
        // which gives the best table fidelity - native wrapping-cell NSTextTable on macOS (TextKit 2
        // would draw single-line grid tables on every platform, losing that). RichText picks the engine
        // at construction; there is no runtime table-based switching to defer to.
        //
        // Unqualified `RichText` is the imported package view (the element type is RichTextView, so
        // nothing local shadows it). Module-qualifying as `RichText.RichText` does NOT work: `import
        // RichText` brings the type `RichText` into scope, which shadows the module name of the same name.
        return RichText(markdown: markdown, theme: theme)
    }

    // Baseline View modifiers (frame, padding, background, cornerRadius, opacity, ...) are applied by the registry.
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Value-primary element. The "markdown" JSON seed is resolved inside buildView (an external add-on
    // cannot read model.validatedProperties - it is internal to ActionUI), so initialValue only reflects
    // the runtime value. Returns "" (not nil) when no value is set yet, so the non-Void String valueType
    // has a non-nil initial value - mirroring the other add-ons and avoiding the engine's "initial value
    // not provided" error. An empty string means "no runtime source", and buildView then falls back to
    // the "markdown" property.
    static var initialValue: (ViewModel) -> Any? = { model in (model.value as? String) ?? "" }

    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    // Leaf view: no child containers accept runtime insertions.
    static var insertableContainers: [String: ContainerShape]? = nil
}

// MARK: - Property coercion (this module cannot see ActionUI's internal Dictionary+Numeric helper)

/// Coerces a JSON-decoded numeric value to CGFloat, matching the numeric types ActionUI's decoder
/// produces (Int / Double / Float / CGFloat). Returns nil for non-numeric values (Bool does not
/// cast to Int/Double via `as?`, so a JSON boolean is correctly rejected).
private func numericCGFloat(_ any: Any?) -> CGFloat? {
    switch any {
    case let value as CGFloat: return value
    case let value as Double: return CGFloat(value)
    case let value as Int: return CGFloat(value)
    case let value as Float: return CGFloat(value)
    default: return nil
    }
}
