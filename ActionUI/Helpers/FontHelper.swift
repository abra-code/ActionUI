import SwiftUI

#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Helper to resolve font styles and sizes from JSON properties for SwiftUI views.
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
    
    /// Maps a font property (SwiftUI font role or custom font name) to a SwiftUI Font.
    /// - Parameter font: The font property from JSON (e.g., "largeTitle", "Helvetica").
    /// - Returns: A SwiftUI Font, defaulting to .body if invalid or nil.
    static func resolveFont(_ font: Any?, _ logger: any ActionUILogger) -> Font {
        guard let fontString = font as? String else {
            logger.log("Font must be a string; defaulting to 'body'", .warning)
            return .body
        }
        
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
        default: return .custom(fontString, size: bodyFontSize, relativeTo: .body) // Custom font with Dynamic Type
        }
    }
}
