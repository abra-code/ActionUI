import SwiftUI

#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Turns a font property (FontSpec, Core/Helpers/FontSpec.swift) into a SwiftUI Font.
///
/// Supports two forms:
/// - **String**: Named text style (`"body"`, `"title"`, etc.) or custom font name (`"Menlo"`).
/// - **Dictionary**: `{ "name": "Menlo", "size": 12, "weight": "bold", "design": "monospaced" }`
///   - `"name"` (String, optional): Font family name. Omit for system font.
///   - `"size"` (Number, required): Point size.
///   - `"weight"` (String, optional): ultraLight, thin, light, regular, medium, semibold, bold, heavy, black.
///   - `"design"` (String, optional): default, monospaced, rounded, serif.
struct FontHelper {
    /// Lazily computed base font size for the `body` text style, matching SwiftUI's `Font.body`.
    static let bodyFontSize: CGFloat = {
        #if os(iOS) || os(watchOS) || os(tvOS)
        return UIFont.preferredFont(forTextStyle: .body).pointSize
        #elseif os(macOS)
        return NSFont.preferredFont(forTextStyle: .body).pointSize
        #else
        return 17.0 // Fallback for unsupported platforms
        #endif
    }()

    /// Resolves a font property (String or Dictionary) to a SwiftUI Font (FontSpec in
    /// Core/Helpers/FontSpec.swift parses it).
    static func resolveFont(_ font: Any?, _ logger: any ActionUILogger) -> Font {
        self.font(for: FontSpec.parse(font, logger: logger))
    }

    /// The SwiftUI Font for a parsed font property.
    static func font(for spec: FontSpec) -> Font {
        switch spec {
        case let .textStyle(style):
            return textStyle(style)
        case let .named(name):
            return .custom(name, size: bodyFontSize, relativeTo: .body)
        case let .sized(name, size, weight, design):
            var font: Font
            if let name {
                font = .custom(name, size: CGFloat(size))
            } else {
                font = .system(size: CGFloat(size), design: self.design(design))
            }
            if let weight {
                font = font.weight(self.weight(weight))
            }
            return font
        }
    }

    private static func textStyle(_ style: FontTextStyle) -> Font {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption
        case .caption2: return .caption2
        case .footnote: return .footnote
        }
    }

    private static func weight(_ weight: FontWeight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    private static func design(_ design: FontDesign) -> Font.Design {
        switch design {
        case .default: return .default
        case .monospaced: return .monospaced
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }
}
