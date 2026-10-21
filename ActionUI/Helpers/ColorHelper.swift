/*
 ColorHelper turns ColorSpec and ShapeStyleSpec (Core/Helpers/ColorSpec.swift), parsed from a document's color strings, into SwiftUI colors and shape styles, and a SwiftUI Color into hex.
 Used by ColorPicker and other views requiring color manipulation.
 */

// import UIKit
import SwiftUI

class ColorHelper {
    // The color SwiftUI itself gives a shadow when none is named, for both View.shadow(color:radius:x:y:)
    // and GraphicsContext.Filter.shadow: black at a third opacity. Opaque black reads as a heavy,
    // dark smudge.
    static let defaultShadowColor = SwiftUI.Color(.sRGBLinear, white: 0, opacity: 0.33)

    // A SwiftUI Color for a color string (Core/Helpers/ColorSpec.swift says which forms), or nil
    // when the string describes none.
    static func resolveColor(_ string: String?) -> SwiftUI.Color? {
        ColorSpec.parse(string).map(color(for:))
    }

    static func color(for spec: ColorSpec) -> SwiftUI.Color {
        switch spec {
        case let .rgba(red, green, blue, alpha):
            return SwiftUI.Color(red: red, green: green, blue: blue, opacity: alpha)
        case let .named(name):
            return color(named: name)
        case let .withOpacity(base, opacity):
            return color(for: base).opacity(opacity)
        }
    }

    private static func color(named name: ColorName) -> SwiftUI.Color {
        switch name {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .indigo: return .indigo
        case .brown: return .brown
        case .gray: return .gray
        case .black: return .black
        case .white: return .white
        case .clear: return .clear
        case .primary: return .primary
        case .secondary: return .secondary
        case .accentColor: return .accentColor
        }
    }

    // Converts a SwiftUI Color to a hex string
    // Returns #RRGGBB for opaque colors, #RRGGBBAA for non-opaque
    // Design decision: Uses platform-specific APIs (NSColor/UIColor) for accurate RGBA extraction
    static func colorToHex(_ color: SwiftUI.Color) -> String? {
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
    
    // A SwiftUI color as a ColorSpec: its sRGB components, read as colorToHex reads them. nil when
    // the platform cannot convert the color to sRGB.
    static func spec(from color: SwiftUI.Color) -> ColorSpec? {
        #if os(macOS)
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return .rgba(red: Double(nsColor.redComponent), green: Double(nsColor.greenComponent),
                     blue: Double(nsColor.blueComponent), alpha: Double(nsColor.alphaComponent))
        #else
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = UIColor(color).cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 4 else { return nil }
        return .rgba(red: Double(components[0]), green: Double(components[1]),
                     blue: Double(components[2]), alpha: Double(components[3]))
        #endif
    }

    // A SwiftUI color a Swift host passes to setElementValue, as a ColorSpec: one of the named
    // colors when it is one (so .red or .primary keeps following light and dark mode), else its
    // sRGB components in the current appearance.
    static func hostSpec(for color: SwiftUI.Color) -> ColorSpec? {
        if let name = ColorName.allCases.first(where: { self.color(for: .named($0)) == color }) {
            return .named(name)
        }
        return spec(from: color)
    }

    // A SwiftUI ShapeStyle for a style string: a semantic style ("background.secondary",
    // "separator", ...) or a color (ShapeStyleSpec in Core/Helpers/ColorSpec.swift); nil for neither.
    static func resolveShapeStyle(_ string: String) -> (any ShapeStyle)? {
        ShapeStyleSpec.parse(string).map(shapeStyle(for:))
    }

    static func shapeStyle(for spec: ShapeStyleSpec) -> any ShapeStyle {
        switch spec {
        case let .color(spec):
            return color(for: spec)
        case let .style(name):
            switch name {
            case .background: return .background
            case .backgroundSecondary: return .background.secondary
            case .backgroundTertiary: return .background.tertiary
            case .backgroundQuaternary: return .background.quaternary
            case .foreground: return .foreground
            case .foregroundSecondary: return .foreground.secondary
            case .foregroundTertiary: return .foreground.tertiary
            case .foregroundQuaternary: return .foreground.quaternary
            case .primary: return .primary
            case .secondary: return .secondary
            case .tertiary: return .tertiary
            case .quaternary: return .quaternary
            case .quinary: return .quinary
            case .separator: return .separator
            case .tint: return .tint
            case .fill: return .fill
            case .fillSecondary: return .fill.secondary
            case .fillTertiary: return .fill.tertiary
            case .fillQuaternary: return .fill.quaternary
            case .placeholder: return .placeholder
            case .link: return .link
            case .selection: return .selection
            case .windowBackground: return .windowBackground
            }
        }
    }
}
