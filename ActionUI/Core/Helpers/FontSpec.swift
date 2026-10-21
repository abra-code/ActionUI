// Core/Helpers/FontSpec.swift
/*
 A font as an ActionUI document writes it, parsed into a portable description that each renderer
 turns into its own font (SwiftUI: Helpers/FontHelper.swift).

 Two forms:
   - a string: a text style ("body", "title", ...; FontTextStyle) or a font name ("Menlo"), drawn
     at the body size and scaled with it;
   - an object: { "name": "Menlo", "size": 12, "weight": "bold", "design": "monospaced" } - size
     required, name optional (the system font without it), weight and design optional.
 Names are compared exactly.
*/

enum FontTextStyle: String, CaseIterable, Sendable {
    case largeTitle, title, title2, title3, headline, subheadline, body, callout, caption, caption2, footnote
}

enum FontWeight: String, CaseIterable, Sendable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
}

enum FontDesign: String, CaseIterable, Sendable {
    case `default`, monospaced, rounded, serif
}

enum FontSpec: Sendable, Equatable {
    /// A text style, which follows the user's text size.
    case textStyle(FontTextStyle)
    /// A font by name at the body text style's size, scaled with it.
    case named(String)
    /// A font of a fixed size: the named font (`design` unused), or the system font in `design`.
    case sized(name: String?, size: Double, weight: FontWeight?, design: FontDesign)

    /// The font `value` describes. A value that describes none is the body text style, with a
    /// warning; an unknown weight is ignored and an unknown design is the default, each with a
    /// warning.
    static func parse(_ value: Any?, logger: any ActionUILogger) -> FontSpec {
        if let text = value as? String {
            return FontTextStyle(rawValue: text).map { .textStyle($0) } ?? .named(text)
        }
        guard let dict = value as? [String: Any] else {
            logger.log("Font must be a String or Dictionary; defaulting to 'body'", .warning)
            return .textStyle(.body)
        }
        guard let size = dict.double(forKey: "size") else {
            logger.log("Font dictionary requires 'size'; defaulting to body", .warning)
            return .textStyle(.body)
        }
        var weight: FontWeight?
        if let text = dict["weight"] as? String {
            weight = FontWeight(rawValue: text)
            if weight == nil {
                logger.log("Unknown font weight '\(text)'; ignoring", .warning)
            }
        }
        var design = FontDesign.default
        if let text = dict["design"] as? String {
            if let known = FontDesign(rawValue: text) {
                design = known
            } else {
                logger.log("Unknown font design '\(text)'; using default", .warning)
            }
        }
        return .sized(name: dict["name"] as? String, size: size, weight: weight, design: design)
    }
}
