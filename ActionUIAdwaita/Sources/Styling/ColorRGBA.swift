// Sources/Styling/ColorRGBA.swift
/*
 Colors (Core's ColorSpec) as GDK colors, for what draws them itself (Canvas) rather than through
 CSS: the same colors ColorCSS gives the CSS-styled elements. Named colors are libadwaita's
 palette (the same in light and dark mode), Apple's light-mode system color where libadwaita has
 none, and primary, secondary and the accent color as libadwaita shows them in the current mode.
 A test compares every named color with what GTK resolves from ColorCSS's value.
*/

import CAdwaita

@MainActor
enum ColorRGBA {
    /// `color` as drawn in `widget`, whose text color secondary is made from.
    static func resolve(_ color: ColorSpec, for widget: WidgetPointer) -> GdkRGBA {
        switch color {
        case let .rgba(red, green, blue, alpha):
            return GdkRGBA(red: Float(clamped(red)), green: Float(clamped(green)), blue: Float(clamped(blue)), alpha: Float(clamped(alpha)))
        case let .named(name):
            return resolve(name, for: widget)
        case let .withOpacity(base, opacity):
            var rgba = resolve(base, for: widget)
            rgba.alpha *= Float(clamped(opacity))
            return rgba
        }
    }

    /// A named color, as ColorCSS.value(name) resolves.
    static func resolve(_ name: ColorName, for widget: WidgetPointer) -> GdkRGBA {
        let manager = adw_style_manager_get_default()
        let dark = adw_style_manager_get_dark(manager) != 0
        switch name {
        case .primary:
            // libadwaita's window foreground.
            return dark ? hex(0xffffff) : GdkRGBA(red: 0, green: 0, blue: 6.0 / 255, alpha: 0.8)
        case .secondary:
            var color = GdkRGBA()
            gtk_widget_get_color(widget, &color)
            color.alpha *= 0.55
            return color
        case .accentColor:
            var color = GdkRGBA()
            adw_accent_color_to_standalone_rgba(adw_style_manager_get_accent_color(manager), dark ? 1 : 0, &color)
            return color
        case .clear: return GdkRGBA(red: 0, green: 0, blue: 0, alpha: 0)
        case .red: return hex(0xe01b24)
        case .orange: return hex(0xff7800)
        case .yellow: return hex(0xf6d32d)
        case .green: return hex(0x2ec27e)
        case .blue: return hex(0x3584e4)
        case .purple: return hex(0x9141ac)
        case .brown: return hex(0x986a44)
        case .gray: return hex(0x8e8e93)
        case .pink: return hex(0xff2d55)
        case .mint: return hex(0x00c7be)
        case .teal: return hex(0x30b0c7)
        case .cyan: return hex(0x32ade6)
        case .indigo: return hex(0x5856d6)
        case .black: return hex(0x000000)
        case .white: return hex(0xffffff)
        }
    }

    private static func hex(_ value: UInt32) -> GdkRGBA {
        GdkRGBA(red: Float((value >> 16) & 0xff) / 255, green: Float((value >> 8) & 0xff) / 255, blue: Float(value & 0xff) / 255, alpha: 1)
    }

    private static func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
