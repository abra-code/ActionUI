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
enum ColorName: String, CaseIterable, Sendable {
    case red, blue, green, yellow, orange, purple, pink, mint, teal, cyan, indigo, brown, gray
    case black, white, clear
    case primary, secondary
    case accentColor = "accentcolor"
}

indirect enum ColorSpec: Sendable, Equatable {
    /// Components in 0...1.
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    case named(ColorName)
    /// `base` drawn at `opacity` (0...1).
    case withOpacity(ColorSpec, Double)

    /// The color `text` describes, or nil when it describes none.
    static func parse(_ text: String?) -> ColorSpec? {
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
