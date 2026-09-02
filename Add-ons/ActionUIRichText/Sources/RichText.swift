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
     "syntaxHighlighting": true,             // Optional: Bool; color fenced code blocks by language. Default from
                                             //           the RichText theme.
     "widthBehavior": "fill",                // Optional: "fill" (default) fills the proposed width, left-aligned -
                                             //           block / document layout. "hug" sizes to the content
                                             //           width, wrapping only when it exceeds the proposal (the
                                             //           messaging-bubble idiom; pair with frame.maxWidth to cap).
     "showFindBar": false                    // Optional: Bool (default false); a find bar over this document
                                             //           (Cmd-F to open, Cmd-G / Shift-Cmd-G next / previous, Escape
                                             //           to close, options for case / whole word / diacritics).
                                             //           Matches are painted behind the text without re-laying it
                                             //           out. Off, states["search"] still highlights (see below).
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

 Runtime state (via setElementState):
   states["search"] (String)   A query: a non-empty value highlights every match and presents the find
                               bar with the term when "showFindBar" is on (without taking the keyboard focus);
                               "" clears. The element seeds the key as a String, so any text is accepted
                               (core fixes a state key's type on its first write). The channel re-delivers
                               its value on every states change, so a value equal to the last applied one
                               is ignored - the reader can close the bar without it springing back; to
                               re-open with the same term, set "" and then the term again.
                               The element highlights; it does not scroll. Bringing the current match
                               into view needs a scroller that reads RichText's current-match anchor,
                               which ActionUI's ScrollView does not yet, and the bar is inset on the
                               element itself, so a long document is best given its own ScrollView.
                               Cmd-F belongs to the element with "showFindBar" on; two in one window contend
                               for it. Cmd-G / Shift-Cmd-G / Escape exist only while the bar is shown.

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

        if let behavior = validated["widthBehavior"] {
            if let string = behavior as? String, string == "fill" || string == "hug" {
                // valid
            } else {
                logger.log("RichText widthBehavior must be \"fill\" or \"hug\"; ignoring", .warning)
                validated["widthBehavior"] = nil
            }
        }

        if let find = validated["showFindBar"], !(find is Bool) {
            logger.log("RichText showFindBar must be a Bool; ignoring", .warning)
            validated["showFindBar"] = nil
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
        // "fill" (default) fills the proposed width like a document block; "hug" sizes to the content and
        // wraps only at the proposal - pair it with frame.maxWidth for a content-hugging bubble.
        let behavior: RichTextWidthBehavior = (properties["widthBehavior"] as? String) == "hug" ? .hug : .fill

        // The find layers ride on the element's SwiftUI body (RichTextElementView), which owns the find
        // controller, renders the Markdown once per source, and observes states["search"].
        return RichTextElementView(model: model, markdown: markdown, theme: theme, behavior: behavior,
                                   showsFindBar: (properties["showFindBar"] as? Bool) ?? false, logger: logger)
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

    // The "search" state is seeded as an empty String: a state key's FIRST write fixes its type (a
    // host writing "42" through the string setter would pin it to Int and every later term would be
    // refused), and the terms on this channel are typed by people. An empty value dismisses nothing.
    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states["search"] == nil {
            states["search"] = ""
        }
        return states
    }

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
