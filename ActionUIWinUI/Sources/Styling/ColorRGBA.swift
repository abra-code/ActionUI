// Sources/Styling/ColorRGBA.swift
/*
 Colors (Core's ColorSpec) as the shim's ActionUIWinUIColor. The named hues (red, blue, ...) are
 SwiftUI's light-mode values, as the GTK renderer uses them where its own palette has none: Windows
 has no named palette of its own. A translucent color (.opacity) multiplies the alpha. What follows
 the system (primary, secondary, accentColor, and the semantic styles) is the WinUI theme's brush
 instead (Paint); the values below for those are only a fallback.

 Not yet: dark-mode values of the named hues.
*/

import CWinUI

enum ColorRGBA {
    /// `color` as red, green, blue and alpha in 0...1.
    static func resolve(_ color: ColorSpec) -> ActionUIWinUIColor {
        switch color {
        case let .rgba(red, green, blue, alpha):
            return ActionUIWinUIColor(red: red, green: green, blue: blue, alpha: alpha)
        case let .named(name):
            return named(name)
        case let .withOpacity(base, opacity):
            var resolved = resolve(base)
            resolved.alpha *= opacity
            return resolved
        }
    }

    /// The color a document's color string names; nil when it is not a color (a semantic style, or
    /// not a color at all).
    static func parse(_ text: String?) -> ActionUIWinUIColor? {
        ColorSpec.parse(text).map(resolve)
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> ActionUIWinUIColor {
        ActionUIWinUIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    private static func named(_ name: ColorName) -> ActionUIWinUIColor {
        switch name {
        case .red: return rgb(255, 59, 48)
        case .orange: return rgb(255, 149, 0)
        case .yellow: return rgb(255, 204, 0)
        case .green: return rgb(52, 199, 89)
        case .mint: return rgb(0, 199, 190)
        case .teal: return rgb(48, 176, 199)
        case .cyan: return rgb(50, 173, 230)
        case .blue, .accentColor: return rgb(0, 122, 255)
        case .indigo: return rgb(88, 86, 214)
        case .purple: return rgb(175, 82, 222)
        case .pink: return rgb(255, 45, 85)
        case .brown: return rgb(162, 132, 94)
        case .gray: return rgb(142, 142, 147)
        case .black: return rgb(0, 0, 0)
        case .white: return rgb(255, 255, 255)
        case .clear: return rgb(0, 0, 0, 0)
        case .primary: return rgb(0, 0, 0, 0.85)
        case .secondary: return rgb(0, 0, 0, 0.5)
        }
    }
}
