// Sources/Styling/FontCSS.swift
/*
 Fonts (Core's FontSpec) as libadwaita style classes and CSS declarations. Text styles map to
 libadwaita's typography classes, which is how GNOME apps show titles and captions:

   largeTitle title-1, title title-2, title2 title-3, title3 title-4, headline heading,
   subheadline 85% (regular weight, as SwiftUI's; libadwaita's caption-heading is bold), body
   and callout the default, footnote and caption caption,
   caption2 caption at 70%: 0.85 of caption, whose 82% the 70% replaces (both are of the parent
   font size).

 A sized font sets font-size in pixels (one SwiftUI point is one GTK pixel; tenths kept, at most
 maximumSize, beyond which GTK's renderers and FreeType fail), its weight as a CSS
 weight, and its family: the name it gives, "monospace" or "serif" for those designs (the
 monospaced design also gets libadwaita's monospace class). The rounded design has no common
 Linux font and uses the default.

 A font name comes from the document and is written into CSS, so it is quoted and stripped of
 anything that could end the string.
*/

enum FontCSS {
    /// The style classes and declarations for a font.
    static func style(_ font: FontSpec) -> (classes: [String], declarations: [String]) {
        switch font {
        case let .textStyle(style):
            return textStyle(style)
        case let .named(name):
            return ([], ["font-family: \(quoted(name));"])
        case let .sized(name, size, weight, design):
            var classes: [String] = []
            var declarations: [String] = []
            if size.isFinite, size > 0 {
                declarations.append("font-size: \(pixels(size))px;")
            }
            if let weight {
                declarations.append("font-weight: \(cssWeight(weight));")
            }
            if let name {
                declarations.append("font-family: \(quoted(name));")
            } else {
                switch design {
                case .monospaced:
                    classes.append("monospace")
                    declarations.append("font-family: monospace;")
                case .serif:
                    declarations.append("font-family: serif;")
                case .default, .rounded:
                    break
                }
            }
            return (classes, declarations)
        }
    }

    static func textStyle(_ style: FontTextStyle) -> (classes: [String], declarations: [String]) {
        switch style {
        case .largeTitle: return (["title-1"], [])
        case .title: return (["title-2"], [])
        case .title2: return (["title-3"], [])
        case .title3: return (["title-4"], [])
        case .headline: return (["heading"], [])
        case .subheadline: return ([], ["font-size: 85%;"])
        case .body, .callout: return ([], [])
        case .footnote, .caption: return (["caption"], [])
        case .caption2: return (["caption"], ["font-size: 70%;"])
        }
    }

    /// The largest font size written. Measured in the box: from about 8000 px a label grows its
    /// window past what the renderer can draw, and from 65536 px FreeType fails.
    static let maximumSize = 4096.0

    /// A positive size in pixels with at most one decimal, never in exponent form, at least 0.1
    /// and at most maximumSize.
    static func pixels(_ size: Double) -> String {
        guard size.isFinite else { return "\(Int(maximumSize))" }
        let tenths = max(Int((min(size, maximumSize) * 10).rounded()), 1)
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    static func cssWeight(_ weight: FontWeight) -> Int {
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

    /// `name` as a CSS string: quotes and backslashes escaped, control characters and anything
    /// past the first line dropped, so it cannot end the string or the rule.
    static func quoted(_ name: String) -> String {
        var text = ""
        for scalar in name.unicodeScalars {
            if scalar == "\n" || scalar == "\r" { break }
            if scalar.value < 0x20 || scalar.value == 0x7F { continue }
            if scalar == "\"" || scalar == "\\" { text.append("\\") }
            text.unicodeScalars.append(scalar)
        }
        return "\"\(text)\""
    }
}
