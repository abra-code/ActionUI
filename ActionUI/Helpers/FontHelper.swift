import SwiftUI

#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Helper to resolve font styles and sizes from JSON properties for SwiftUI views.
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

    /// Resolves a font property (String or Dictionary) to a SwiftUI Font.
    static func resolveFont(_ font: Any?, _ logger: any ActionUILogger) -> Font {
        if let fontString = font as? String {
            return resolveFontFromString(fontString)
        }
        if let fontDict = font as? [String: Any] {
            return resolveFontFromDictionary(fontDict, logger)
        }
        logger.log("Font must be a String or Dictionary; defaulting to 'body'", .warning)
        return .body
    }

    /// Resolves a string font value: named text style or custom font name.
    private static func resolveFontFromString(_ fontString: String) -> Font {
        switch fontString {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "body": return .body
        case "callout": return .callout
        case "caption": return .caption
        case "caption2": return .caption2
        case "footnote": return .footnote
        default: return .custom(fontString, size: bodyFontSize, relativeTo: .body)
        }
    }

    /// Resolves a dictionary font value: `{ "name", "size", "weight", "design" }`.
    private static func resolveFontFromDictionary(_ dict: [String: Any], _ logger: any ActionUILogger) -> Font {
        guard let size = dict.cgFloat(forKey: "size") else {
            logger.log("Font dictionary requires 'size'; defaulting to body", .warning)
            return .body
        }

        let name = dict["name"] as? String
        let weight = resolveWeight(dict["weight"] as? String, logger)
        let design = resolveDesign(dict["design"] as? String, logger)

        if let name = name {
            // Custom named font
            var font = Font.custom(name, size: size)
            if let weight = weight {
                font = font.weight(weight)
            }
            return font
        } else {
            // System font
            var font = Font.system(size: size, design: design)
            if let weight = weight {
                font = font.weight(weight)
            }
            return font
        }
    }

    private static func resolveWeight(_ value: String?, _ logger: any ActionUILogger) -> Font.Weight? {
        guard let value = value else { return nil }
        switch value {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default:
            logger.log("Unknown font weight '\(value)'; ignoring", .warning)
            return nil
        }
    }

    private static func resolveDesign(_ value: String?, _ logger: any ActionUILogger) -> Font.Design {
        guard let value = value else { return .default }
        switch value {
        case "default": return .default
        case "monospaced": return .monospaced
        case "rounded": return .rounded
        case "serif": return .serif
        default:
            logger.log("Unknown font design '\(value)'; using default", .warning)
            return .default
        }
    }
}
