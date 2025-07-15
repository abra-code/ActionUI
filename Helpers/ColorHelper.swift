import SwiftUI

/// Extension to support hex RGBA colors.
extension Color {
    init?(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: cleanHex)
        var rgbValue: UInt64 = 0
        guard scanner.scanHexInt64(&rgbValue) else { return nil }
        
        let r, g, b, a: Double
        if cleanHex.count == 6 { // RGB (e.g., #FF0000)
            r = Double((rgbValue >> 16) & 0xFF) / 255.0
            g = Double((rgbValue >> 8) & 0xFF) / 255.0
            b = Double(rgbValue & 0xFF) / 255.0
            a = 1.0
        } else if cleanHex.count == 8 { // RGBA (e.g., #FF0000FF)
            r = Double((rgbValue >> 24) & 0xFF) / 255.0
            g = Double((rgbValue >> 16) & 0xFF) / 255.0
            b = Double((rgbValue >> 8) & 0xFF) / 255.0
            a = Double(rgbValue & 0xFF) / 255.0
        } else {
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Helper to resolve color properties from JSON for SwiftUI views.
struct ColorHelper {
    /// Maps a color property (named color or hex RGBA) to a SwiftUI Color.
    /// - Parameter color: The color property from JSON (e.g., "red", "#FF0000").
    /// - Returns: A SwiftUI Color, or nil if invalid (defaults to primary in views).
    static func resolveColor(_ color: Any?) -> Color? {
        guard let colorString = color as? String else {
            print("Warning: Color must be a string; defaulting to nil")
            return nil
        }
        
        switch colorString {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "brown": return .brown
        case "gray": return .gray
        case "black": return .black
        case "white": return .white
        case "primary": return .primary
        case "secondary": return .secondary
        default:
            if colorString.hasPrefix("#") && (colorString.count == 7 || colorString.count == 9) {
                return Color(hex: colorString)
            }
            print("Warning: Color '\(colorString)' invalid; defaulting to nil")
            return nil
        }
    }
}