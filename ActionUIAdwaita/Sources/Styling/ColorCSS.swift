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

    /// A color as red, green, blue and alpha in 0...1, for drawing calls that take components (a
    /// shadow). Named colors take Apple's light-mode values; primary is black and secondary black
    /// at half opacity, and the accent color is blue.
    static func components(_ color: ColorSpec) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        switch color {
        case let .rgba(red, green, blue, alpha):
            func unit(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
            return (unit(red), unit(green), unit(blue), unit(alpha))
        case let .withOpacity(base, opacity):
            let value = components(base)
            return (value.red, value.green, value.blue, value.alpha * (opacity.isFinite ? min(max(opacity, 0), 1) : 1))
        case let .named(name):
            let bytes: (Double, Double, Double, Double)
            switch name {
            case .red: bytes = (255, 59, 48, 1)
            case .orange: bytes = (255, 149, 0, 1)
            case .yellow: bytes = (255, 204, 0, 1)
            case .green: bytes = (52, 199, 89, 1)
            case .blue, .accentColor: bytes = (0, 122, 255, 1)
            case .purple: bytes = (175, 82, 222, 1)
            case .pink: bytes = (255, 45, 85, 1)
            case .mint: bytes = (0, 199, 190, 1)
            case .teal: bytes = (48, 176, 199, 1)
            case .cyan: bytes = (50, 173, 230, 1)
            case .indigo: bytes = (88, 86, 214, 1)
            case .brown: bytes = (162, 132, 94, 1)
            case .gray: bytes = (142, 142, 147, 1)
            case .black, .primary: bytes = (0, 0, 0, 1)
            case .secondary: bytes = (0, 0, 0, 0.5)
            case .white: bytes = (255, 255, 255, 1)
            case .clear: bytes = (0, 0, 0, 0)
            }
            return (bytes.0 / 255, bytes.1 / 255, bytes.2 / 255, bytes.3)
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
