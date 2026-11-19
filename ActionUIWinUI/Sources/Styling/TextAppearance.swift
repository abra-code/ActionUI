// Sources/Styling/TextAppearance.swift
/*
 The font and foreground an element's text is drawn with, which, as in SwiftUI, an element passes
 on to its descendants: a font or foregroundStyle on a VStack reaches every Text in it, and an
 element's own overrides it. RenderNode keeps each node's appearance (its own modifiers over its
 parent's) and syncs the children again when it changes, as the GTK renderer does with its
 environment.

 Fonts are WinUI's own (platform-native): a text style is a step of WinUI's type ramp (Fluent:
 Caption 12, Body 14, Body Strong 14 semibold, Body Large 18, Subtitle 20, Title 28, in Segoe UI);
 a sized font keeps its size and weight; monospaced is Cascadia Mono (Consolas where it is
 missing), serif Cambria; a named font is that family at the body size.

   largeTitle  Title 28 semibold        headline     Body Strong 14 semibold
   title       Subtitle 20 semibold     body, callout  Body 14
   title2      Body Large 18 semibold   subheadline, footnote, caption, caption2  Caption 12
   title3      Body Large 18
*/

import CWinUI

struct TextAppearance: Equatable {
    var font: FontSpec?
    /// A style string (a color or a semantic style), read as a foreground.
    var foreground: String?

    /// This appearance with an element's own font and foregroundStyle over it.
    @MainActor
    func applying(_ modifiers: BaseModifiers) -> TextAppearance {
        var appearance = self
        if let font = modifiers.font {
            appearance.font = FontSpec.parse(font, logger: ActionUIModel.shared.logger)
        }
        if let foreground = modifiers.foregroundStyle {
            appearance.foreground = foreground
        }
        return appearance
    }

    /// WinUI's font for `font`: family (nil: Segoe UI), size (0: the theme's) and weight (0: the
    /// theme's), on WinUI's type ramp.
    static func winUIFont(_ font: FontSpec?) -> (family: String?, size: Double, weight: Int32) {
        guard let font else { return (nil, 0, 0) }
        switch font {
        case let .textStyle(style):
            switch style {
            case .largeTitle: return (nil, 28, 600)
            case .title: return (nil, 20, 600)
            case .title2: return (nil, 18, 600)
            case .title3: return (nil, 18, 0)
            case .headline: return (nil, 14, 600)
            case .body, .callout: return (nil, 14, 0)
            case .subheadline, .footnote, .caption, .caption2: return (nil, 12, 0)
            }
        case let .named(name):
            return (name, 0, 0)
        case let .sized(name, size, weight, design):
            let family: String?
            if let name {
                family = name
            } else {
                switch design {
                case .monospaced: family = "Cascadia Mono, Consolas"
                case .serif: family = "Cambria"
                case .default, .rounded: family = nil
                }
            }
            return (family, size, weight.map(numericWeight) ?? 0)
        }
    }

    static func numericWeight(_ weight: FontWeight) -> Int32 {
        switch weight {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        }
    }

    /// Draws `view`'s text (a TextBlock's, or a control's) with this appearance.
    @MainActor
    func apply(to view: WinUIObject, what: String) {
        let (family, size, weight) = Self.winUIFont(font)
        if !actionUIWinUIElementSetFont(view.pointer, family, size, weight) {
            ActionUIModel.shared.logger.log("TextAppearance: \(WinUIError.last("setting the font of \(what)"))", .error)
        }
        Paint.apply(Paint.parse(foreground, role: .foreground), ActionUIWinUIBrushForeground, to: view, what: what)
    }
}
