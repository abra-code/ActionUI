/*
 ColorHelper provides utility functions for converting between SwiftUI Color and string representations (hex or named colors).
 Used by ColorPicker and other views requiring color manipulation.
 */

// import UIKit
import SwiftUI

class ColorHelper {
    // Resolves a string to a SwiftUI Color
    // Supports named colors (e.g., "red", "orange", "clear", "accentColor") and hex formats (#RGB, #RGBA, #RRGGBB, #RRGGBBAA)
    // Returns nil if the string is invalid
    // Design decision: Includes all SwiftUI predefined colors with direct dot notation for compatibility and flexibility
    static func resolveColor(_ string: String?) -> Color? {
        guard let string = string else {
            return nil
        }
        
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Named color mapping
        // Design decision: Maps all SwiftUI predefined colors (standard and semantic) to support comprehensive color input
        let namedColors: [String: Color] = [
            "red": .red,
            "blue": .blue,
            "green": .green,
            "yellow": .yellow,
            "orange": .orange,
            "purple": .purple,
            "pink": .pink,
            "mint": .mint,
            "teal": .teal,
            "cyan": .cyan,
            "indigo": .indigo,
            "brown": .brown,
            "gray": .gray,
            "black": .black,
            "white": .white,
            "clear": .clear,
            "primary": .primary,
            "secondary": .secondary,
            "accentcolor": .accentColor,
        ]
        
        if let namedColor = namedColors[normalized] {
            return namedColor
        }
        
        // Hex color parsing
        let hexSanitized = normalized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r, g, b, a: Double
        
        switch hexSanitized.count {
        case 3: // #RGB
            r = Double((rgb >> 8) & 0xF) / 15.0
            g = Double((rgb >> 4) & 0xF) / 15.0
            b = Double(rgb & 0xF) / 15.0
            a = 1.0
        case 4: // #RGBA
            r = Double((rgb >> 12) & 0xF) / 15.0
            g = Double((rgb >> 8) & 0xF) / 15.0
            b = Double((rgb >> 4) & 0xF) / 15.0
            a = Double(rgb & 0xF) / 15.0
        case 6: // #RRGGBB
            r = Double((rgb >> 16) & 0xFF) / 255.0
            g = Double((rgb >> 8) & 0xFF) / 255.0
            b = Double(rgb & 0xFF) / 255.0
            a = 1.0
        case 8: // #RRGGBBAA
            r = Double((rgb >> 24) & 0xFF) / 255.0
            g = Double((rgb >> 16) & 0xFF) / 255.0
            b = Double((rgb >> 8) & 0xFF) / 255.0
            a = Double(rgb & 0xFF) / 255.0
        default:
            return nil
        }
        
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    
    // Converts a SwiftUI Color to a hex string
    // Returns #RRGGBB for opaque colors, #RRGGBBAA for non-opaque
    // Design decision: Uses platform-specific APIs (NSColor/UIColor) for accurate RGBA extraction
    static func colorToHex(_ color: Color) -> String? {
        #if os(macOS)
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = Int(nsColor.redComponent * 255.0)
        let g = Int(nsColor.greenComponent * 255.0)
        let b = Int(nsColor.blueComponent * 255.0)
        let a = nsColor.alphaComponent
        #else
        guard let uiColor = UIColor(color).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = uiColor.components else { return nil }
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        let a = components[3]
        #endif
        
        if a >= 1.0 {
            return String(format: "#%02X%02X%02X", r, g, b)
        } else {
            let aInt = Int(a * 255.0)
            return String(format: "#%02X%02X%02X%02X", r, g, b, aInt)
        }
    }
    
    // Resolves a string to a SwiftUI ShapeStyle (semantic or color)
    // Checks for semantic named styles, falls back to resolveColor()
    // Supported semantic styles: background, foreground, primary, secondary, tertiary, quaternary, separator, placeholder
    static func resolveShapeStyle(_ string: String) -> (any ShapeStyle)? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "background":
            return .background
        case "foreground":
            return .foreground
        case "primary":
            return .primary
        case "secondary":
            return .secondary
        case "tertiary":
            return .tertiary
        case "quaternary":
            return .quaternary
        case "quinary":
        	return .quinary
        case "separator":
            return .separator
        case "tint":
            return .tint
        case "fill":
        	return .fill
        case "placeholder":
            return .placeholder
        case "link":
            return .link
        case "selection":
        	return .selection
        case "windowBackground":
        	return .windowBackground
        default:
            if let color = resolveColor(string) {
                return color
            } else {
                return nil
            }
        }
    }
}
