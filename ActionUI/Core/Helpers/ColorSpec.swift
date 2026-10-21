// Core/Helpers/ColorSpec.swift
/*
 A color as an ActionUI document writes it, parsed into a portable description that each renderer
 turns into its own color type (SwiftUI: Helpers/ColorHelper.swift).

 Forms accepted, compared without case and leading or trailing white space:
   - a name: "red", "primary", "accentColor", ... (ColorName)
   - hex: "#RGB", "#RGBA", "#RRGGBB", "#RRGGBBAA" (the "#" is optional)
   - "<color>.opacity(<fraction>)": a color made translucent, the fraction clamped to 0...1
 A shape style (ShapeStyleSpec) also accepts the semantic styles a fill or a foreground can use:
 "background", "fill.tertiary", "separator", ...
*/

/// The named colors a document can use. Some follow light and dark mode (primary, secondary,
/// accentColor), so they stay names and each renderer resolves them in its own appearance.
public enum ColorName: String, CaseIterable, Sendable {
    case red, blue, green, yellow, orange, purple, pink, mint, teal, cyan, indigo, brown, gray
    case black, white, clear
    case primary, secondary
    case accentColor = "accentcolor"
}

/// The value of a Color or ColorPicker element, and what every color string in a document parses
/// to. On Apple, ColorHelper turns it into a SwiftUI Color.
public indirect enum ColorSpec: Sendable, Equatable {
    /// Components in 0...1.
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    case named(ColorName)
    /// `base` drawn at `opacity` (0...1).
    case withOpacity(ColorSpec, Double)

    /// The color `text` describes, or nil when it describes none.
    public static func parse(_ text: String?) -> ColorSpec? {
        guard let text else {
            return nil
        }
        let normalized = PlainText.trimmed(text).lowercased()

        if let name = ColorName(rawValue: normalized) {
            return .named(name)
        }

        // "<color>.opacity(<fraction>)", SwiftUI's own spelling of a translucent color.
        if normalized.hasSuffix(")"), let marker = normalized.firstRange(of: ".opacity(") {
            let base = String(normalized[..<marker.lowerBound])
            let inner = normalized[marker.upperBound..<normalized.index(before: normalized.endIndex)]
            if let fraction = Double(PlainText.trimmed(inner)), let baseColor = parse(base) {
                return .withOpacity(baseColor, min(1, max(0, fraction)))
            }
        }

        return hex(normalized.replacing("#", with: ""))
    }

    // The components of an .rgba color, also under any number of .withOpacity (the opacities
    // multiply its alpha); nil for a named color.
    private var components: (Double, Double, Double, Double)? {
        switch self {
        case let .rgba(red, green, blue, alpha):
            return (red, green, blue, alpha)
        case let .withOpacity(base, opacity):
            return base.components.map { ($0.0, $0.1, $0.2, $0.3 * opacity) }
        case .named:
            return nil
        }
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when alpha is below 1, for an `.rgba` color (or one made translucent with `.withOpacity`): each component times
    /// 255, the fraction dropped, as ColorHelper.colorToHex writes a SwiftUI color. nil for a named
    /// color, whose components only a renderer knows (they follow light and dark mode).
    var hexText: String? {
        guard let (red, green, blue, alpha) = components else {
            return nil
        }
        // Clamped before the conversion: a host can build any .rgba, and Int(_:) traps on NaN,
        // infinity and anything beyond Int's range (max(0, .nan) is 0).
        func byte(_ component: Double) -> UInt64 {
            UInt64(min(1, max(0, component)) * 255.0)
        }
        var text = "#" + PlainText.hex(byte(red), width: 2) + PlainText.hex(byte(green), width: 2) + PlainText.hex(byte(blue), width: 2)
        if alpha < 1.0 {
            text += PlainText.hex(byte(alpha), width: 2)
        }
        return text
    }

    // Hex digits only (ASCII: UInt64(_:radix:) would also take a leading "+"), three, four, six or
    // eight of them.
    private static func hex(_ digits: String) -> ColorSpec? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt64(digits, radix: 16) else {
            return nil
        }
        func channel(_ shift: UInt64, _ mask: UInt64) -> Double {
            Double((value >> shift) & mask) / Double(mask)
        }
        switch digits.count {
        case 3:
            return .rgba(red: channel(8, 0xF), green: channel(4, 0xF), blue: channel(0, 0xF), alpha: 1)
        case 4:
            return .rgba(red: channel(12, 0xF), green: channel(8, 0xF), blue: channel(4, 0xF), alpha: channel(0, 0xF))
        case 6:
            return .rgba(red: channel(16, 0xFF), green: channel(8, 0xFF), blue: channel(0, 0xFF), alpha: 1)
        default:
            return .rgba(red: channel(24, 0xFF), green: channel(16, 0xFF), blue: channel(8, 0xFF), alpha: channel(0, 0xFF))
        }
    }
}

/// The semantic styles a fill, background or foreground can name, beyond plain colors.
enum ShapeStyleName: String, CaseIterable, Sendable {
    case background
    case backgroundSecondary = "background.secondary"
    case backgroundTertiary = "background.tertiary"
    case backgroundQuaternary = "background.quaternary"
    case foreground
    case foregroundSecondary = "foreground.secondary"
    case foregroundTertiary = "foreground.tertiary"
    case foregroundQuaternary = "foreground.quaternary"
    case primary, secondary, tertiary, quaternary, quinary
    case separator, tint
    case fill
    case fillSecondary = "fill.secondary"
    case fillTertiary = "fill.tertiary"
    case fillQuaternary = "fill.quaternary"
    case placeholder, link, selection
    case windowBackground = "windowbackground"
}

enum ShapeStyleSpec: Sendable, Equatable {
    case style(ShapeStyleName)
    case color(ColorSpec)

    /// A semantic style, else a color (ColorSpec.parse), else nil. "primary" and "secondary" are
    /// semantic styles here, as SwiftUI's resolveShapeStyle has always read them.
    static func parse(_ text: String) -> ShapeStyleSpec? {
        if let name = ShapeStyleName(rawValue: PlainText.trimmed(text).lowercased()) {
            return .style(name)
        }
        return ColorSpec.parse(text).map { .color($0) }
    }
}
