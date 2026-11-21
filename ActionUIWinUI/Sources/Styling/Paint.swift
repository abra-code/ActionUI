// Sources/Styling/Paint.swift
/*
 What a document's style string paints with on WinUI (Core's ShapeStyleSpec): a color of its own
 (ColorRGBA), or one of the WinUI theme's brushes, so a semantic style looks as a WinUI app looks
 (platform-native): the text colors (TextFillColor...), the accent (Accent...), the control fills
 (ControlFillColor...), the window backgrounds (SolidBackgroundFillColor...) and the divider.

 A style that depends on where it paints (primary is a text color, accentColor fills differently
 as text and as a background) takes the role: foreground or background.

 Theme brushes are looked up when applied: a light/dark switch while running does not reach a
 painted element yet.
*/

import CWinUI

enum Paint: Equatable {
    case color(ActionUIWinUIColor)
    /// A WinUI theme resource's name.
    case theme(String)

    enum Role {
        case foreground, background
    }

    static func == (left: Paint, right: Paint) -> Bool {
        switch (left, right) {
        case let (.color(a), .color(b)):
            return a.red == b.red && a.green == b.green && a.blue == b.blue && a.alpha == b.alpha
        case let (.theme(a), .theme(b)):
            return a == b
        default:
            return false
        }
    }

    /// The paint `text` names for `role`; nil when it names none (or a style WinUI has no brush for).
    /// The tint and link styles paint with `tint` (the element's, TextAppearance) when it is a color.
    static func parse(_ text: String?, role: Role, tint: String? = nil) -> Paint? {
        guard let text, let spec = ShapeStyleSpec.parse(text) else { return nil }
        switch spec {
        case let .style(name):
            if name == .tint || name == .link, let tint, case let .color(color)? = parse(tint, role: role) {
                return .color(color)
            }
            return theme(name, role: role).map { .theme($0) }
        case let .color(color):
            return paint(color, role: role)
        }
    }

    /// A color: its own RGBA, except the named colors that follow the system (primary, secondary,
    /// accentColor), which are the theme's.
    static func paint(_ color: ColorSpec, role: Role) -> Paint {
        if case let .named(name) = color {
            switch name {
            case .primary: return .theme("TextFillColorPrimaryBrush")
            case .secondary: return .theme("TextFillColorSecondaryBrush")
            case .accentColor: return .theme(role == .foreground ? "AccentTextFillColorPrimaryBrush" : "AccentFillColorDefaultBrush")
            default: break
            }
        }
        return .color(ColorRGBA.resolve(color))
    }

    private static func theme(_ name: ShapeStyleName, role: Role) -> String? {
        switch name {
        case .primary, .foreground: return "TextFillColorPrimaryBrush"
        case .secondary, .foregroundSecondary: return "TextFillColorSecondaryBrush"
        case .tertiary, .foregroundTertiary, .placeholder: return "TextFillColorTertiaryBrush"
        case .quaternary, .quinary, .foregroundQuaternary: return "TextFillColorDisabledBrush"
        case .tint, .link: return role == .foreground ? "AccentTextFillColorPrimaryBrush" : "AccentFillColorDefaultBrush"
        case .selection: return "AccentFillColorSelectedTextBackgroundBrush"
        case .separator: return "DividerStrokeColorDefaultBrush"
        case .background, .windowBackground: return "SolidBackgroundFillColorBaseBrush"
        case .backgroundSecondary: return "SolidBackgroundFillColorSecondaryBrush"
        case .backgroundTertiary: return "SolidBackgroundFillColorTertiaryBrush"
        // WinUI's own spelling.
        case .backgroundQuaternary: return "SolidBackgroundFillColorQuarternaryBrush"
        case .fill: return "ControlFillColorDefaultBrush"
        case .fillSecondary: return "ControlFillColorSecondaryBrush"
        case .fillTertiary: return "ControlFillColorTertiaryBrush"
        case .fillQuaternary: return "ControlFillColorDisabledBrush"
        }
    }

    /// Paints `property` of `view`; nil for the element's own default. False (logged) when the shim
    /// refused.
    @MainActor @discardableResult
    static func apply(_ paint: Paint?, _ property: ActionUIWinUIBrushProperty, to view: WinUIObject, what: String) -> Bool {
        let set: Bool
        switch paint {
        case nil:
            set = actionUIWinUIElementSetBrush(view.pointer, property, nil, nil)
        case var .color(color)?:
            set = actionUIWinUIElementSetBrush(view.pointer, property, &color, nil)
        case let .theme(name)?:
            set = actionUIWinUIElementSetBrush(view.pointer, property, nil, name)
        }
        if !set {
            ActionUIModel.shared.logger.log("Paint: \(WinUIError.last("painting \(what)"))", .error)
        }
        return set
    }
}
