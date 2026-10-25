// Sources/Styling/ControlSizeCSS.swift
/*
 SwiftUI's controlSize on GTK: the CSS that makes a control mini, small, large or extra large.
 Regular is GNOME's own size (libadwaita's button is 34 px tall where macOS's is 24), and the other
 sizes keep macOS's proportions to it, measured on macOS 27:

   size        button height  side padding  label font
   mini        13 (0.54)      8 (0.67)       9 (0.69)
   small       20 (0.83)     10 (0.83)      11 (0.85)
   regular     24            12             13
   large       28 (1.17)     14 (1.17)      13
   extraLarge  36 (1.5)      18 (1.5)       13

 so a GNOME button is about 18, 28, 34, 40 and 51 px tall. The side padding scales libadwaita's
 own for the button's content: 17 px for a title alone (text-button), 9 px for an icon and a title
 (image-text-button). An icon alone (image-button) is a square in libadwaita (at least 24 px wide,
 5 px padding) and stays one at each height. A plain button is its label alone on both platforms:
 only its font and icon change. A button with a font of its own keeps it, as SwiftUI's label does.
*/

@MainActor
enum ControlSizeCSS {
    /// What a button shows, which sets libadwaita's side padding for it.
    enum ButtonContent {
        case title, iconAndTitle, icon
    }

    /// A button's declarations for `size`; none for regular (and no size), GNOME's own. A button
    /// with `ownFont` keeps its font size.
    static func button(_ size: BaseModifiers.ControlSizeName?, content: ButtonContent, plain: Bool, ownFont: Bool = false) -> [String] {
        let font = ownFont ? [] : fontScale(size).map { ["font-size: \($0)em;"] } ?? []
        guard !plain else { return font }
        let minHeight: Int, vertical: Int, sideScale: Double
        switch size {
        case .mini?: (minHeight, vertical, sideScale) = (14, 2, 0.67)
        case .small?: (minHeight, vertical, sideScale) = (20, 4, 0.83)
        case .large?: (minHeight, vertical, sideScale) = (28, 6, 1.17)
        case .extraLarge?: (minHeight, vertical, sideScale) = (36, 8, 1.5)
        case .regular?, nil: return []
        }
        let box: [String]
        switch content {
        case .icon:
            box = ["min-width: \(minHeight)px;", "padding: \(vertical)px;"]
        case .title, .iconAndTitle:
            let side = Int(((content == .title ? 17 : 9) * sideScale).rounded())
            box = ["padding: \(vertical)px \(side)px;"]
        }
        return font + ["min-height: \(minHeight)px;"] + box
    }

    /// The label font's size against regular's: macOS's 9 and 11 points against 13; nil for the
    /// sizes that keep regular's font.
    static func fontScale(_ size: BaseModifiers.ControlSizeName?) -> Double? {
        switch size {
        case .mini?: return 0.69
        case .small?: return 0.85
        case .regular?, .large?, .extraLarge?, nil: return nil
        }
    }

    /// An icon's size in a control of `size` when nothing else sets it: GNOME's 16 px scaled as
    /// the font is; nil for 16 px.
    static func iconSize(_ size: BaseModifiers.ControlSizeName?) -> Int? {
        fontScale(size).map { Int((16 * $0).rounded()) }
    }
}
