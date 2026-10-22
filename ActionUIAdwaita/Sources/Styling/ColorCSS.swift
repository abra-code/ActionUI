// Sources/Styling/ColorCSS.swift
/*
 Colors and shape styles (Core's ColorSpec and ShapeStyleSpec) as GTK CSS values. Named colors
 use libadwaita's CSS variables: var(--accent-color) and the window colors follow light and dark
 mode, the palette colors (var(--blue-3), ...) are the same in both, as libadwaita's palette is;
 names libadwaita has no counterpart for use Apple's light-mode system color. Semantic styles
 (fill, separator, the foreground levels) are the current text color at an opacity, so dark mode
 follows.

 Every value is built from parsed numbers and fixed names, never from document text, so it cannot
 carry other CSS.
*/

enum ColorCSS {
    /// The CSS value of a color.
    static func value(_ color: ColorSpec) -> String {
        switch color {
        case let .rgba(red, green, blue, alpha):
            return "rgba(\(channel(red)), \(channel(green)), \(channel(blue)), \(fraction(alpha)))"
        case let .named(name):
            return value(name)
        case let .withOpacity(base, opacity):
            return "alpha(\(value(base)), \(fraction(opacity)))"
        }
    }

    /// The CSS value of a named color.
    static func value(_ name: ColorName) -> String {
        switch name {
        case .primary: return "var(--window-fg-color)"
        case .secondary: return "alpha(currentColor, 0.55)"
        case .accentColor: return "var(--accent-color)"
        case .clear: return "transparent"
        case .red: return "var(--red-3)"
        case .orange: return "var(--orange-3)"
        case .yellow: return "var(--yellow-3)"
        case .green: return "var(--green-4)"
        case .blue: return "var(--blue-3)"
        case .purple: return "var(--purple-3)"
        case .brown: return "var(--brown-3)"
        case .gray: return "#8e8e93"
        case .pink: return "#ff2d55"
        case .mint: return "#00c7be"
        case .teal: return "#30b0c7"
        case .cyan: return "#32ade6"
        case .indigo: return "#5856d6"
        case .black: return "#000000"
        case .white: return "#ffffff"
        }
    }

    /// The CSS value of a shape style (a background or foreground style).
    static func value(_ style: ShapeStyleSpec) -> String {
        switch style {
        case let .color(color):
            return value(color)
        case let .style(name):
            return value(name)
        }
    }

    /// The CSS value of a semantic style.
    static func value(_ name: ShapeStyleName) -> String {
        switch name {
        case .background, .windowBackground: return "var(--window-bg-color)"
        case .backgroundSecondary: return "var(--view-bg-color)"
        case .backgroundTertiary: return "var(--card-bg-color)"
        case .backgroundQuaternary: return "var(--headerbar-bg-color)"
        case .foreground, .primary: return "currentColor"
        case .foregroundSecondary, .secondary: return "alpha(currentColor, 0.55)"
        case .foregroundTertiary, .tertiary: return "alpha(currentColor, 0.3)"
        case .foregroundQuaternary, .quaternary: return "alpha(currentColor, 0.18)"
        case .quinary: return "alpha(currentColor, 0.08)"
        case .separator: return "var(--border-color)"
        case .tint, .link: return "var(--accent-color)"
        case .fill: return "alpha(currentColor, 0.15)"
        case .fillSecondary: return "alpha(currentColor, 0.11)"
        case .fillTertiary: return "alpha(currentColor, 0.08)"
        case .fillQuaternary: return "alpha(currentColor, 0.05)"
        case .placeholder: return "alpha(currentColor, 0.5)"
        case .selection: return "alpha(var(--accent-bg-color), 0.3)"
        }
    }

    /// A component in 0...1 as 0...255.
    private static func channel(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        return Int((min(max(component, 0), 1) * 255).rounded())
    }

    /// A fraction in 0...1 with at most three decimals, never in exponent form.
    private static func fraction(_ value: Double) -> String {
        guard value.isFinite else { return "1" }
        let thousandths = Int((min(max(value, 0), 1) * 1000).rounded())
        switch thousandths {
        case 1000: return "1"
        case 0: return "0"
        default:
            var digits = String(thousandths)
            while digits.count < 3 { digits = "0" + digits }
            while digits.hasSuffix("0") { digits.removeLast() }
            return "0." + digits
        }
    }
}
