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

 The other controls built of libadwaita's 34 px button-like parts scale the same way, each from its
 own side padding (measured in libadwaita 1.7): a menu Picker's dropdown button 10 px, a Menu's or
 DatePicker's menu button 9 px, a ColorPicker's button 5 px (its swatch holds a 16 px part, so a
 mini one is 22 px tall, not 18), a Stepper's buttons square; a segmented Picker's group (3 px
 padding) and its 28 px toggles (8 px a side). Their icons (a Stepper's minus and plus) and a
 dropdown's or menu button's arrow (libadwaita's 16 px arrow node) scale as a button's icons do, or
 they would hold a mini part at 20 px. A TextField or
 SecureField entry (34 px, 9 px a side) shrinks for mini and small as macOS's does (19 and 21
 points against 24) and does not grow past regular, as macOS's does not.
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
        let font = font(size, ownFont: ownFont)
        guard !plain else { return font }
        switch content {
        case .icon: return font + box(size, side: 5, square: true)
        case .title: return font + box(size, side: 17)
        case .iconAndTitle: return font + box(size, side: 9)
        }
    }

    /// The label font for `size`; none for the sizes that keep regular's, or for a control with a
    /// font of its own.
    static func font(_ size: BaseModifiers.ControlSizeName?, ownFont: Bool) -> [String] {
        guard !ownFont, let scale = fontScale(size) else { return [] }
        return ["font-size: \(scale)em;"]
    }

    /// Applies `node`'s inherited control size to a control's font: on `widget`, so its title
    /// follows too; a control with a font of its own keeps it.
    static func applyFont(_ node: RenderNode, to widget: WidgetPointer) {
        let declarations = font(node.environment.controlSize, ownFont: BaseModifiers(node.properties).font != nil)
        StyleSheet.shared.apply(declarations, to: widget, slot: "controlSize")
    }

    /// Applies `declarations` (box, entry, toggleGroup) to the parts of `widget` that `selector`
    /// picks ("{} > dropdown > button"); `slot` tells two such parts apart.
    static func applyPart(_ declarations: [String], to widget: WidgetPointer, selector: String = "{}",
                          slot: String = "controlSizePart") {
        StyleSheet.shared.apply(declarations, to: widget, slot: slot, selector: selector)
    }

    /// A 34 px button-like part's height and padding for `size`, scaled from the `side` padding
    /// libadwaita gives it; a `square` part (an icon alone) is as wide as it is tall. None for
    /// regular.
    static func box(_ size: BaseModifiers.ControlSizeName?, side: Int, square: Bool = false) -> [String] {
        guard let (minHeight, vertical, scale) = boxMetrics(size) else { return [] }
        if square {
            return ["min-height: \(minHeight)px;", "min-width: \(minHeight)px;", "padding: \(vertical)px;"]
        }
        return ["min-height: \(minHeight)px;", "padding: \(vertical)px \(Int((Double(side) * scale).rounded()))px;"]
    }

    /// The minimum height and vertical padding that make a 34 px part (24 and 5 a side) macOS's
    /// proportion of it, and the scale for its side padding; nil for regular.
    private static func boxMetrics(_ size: BaseModifiers.ControlSizeName?) -> (Int, Int, Double)? {
        switch size {
        case .mini?: return (14, 2, 0.67)
        case .small?: return (20, 4, 0.83)
        case .large?: return (28, 6, 1.17)
        case .extraLarge?: return (36, 8, 1.5)
        case .regular?, nil: return nil
        }
    }

    /// The size of the icons in a control's parts for `size`, as a button's scale (iconSize); none
    /// for 16 px. Not for a Button itself, whose iconSize slot sets it.
    static func icons(_ size: BaseModifiers.ControlSizeName?) -> [String] {
        iconSize(size).map { ["-gtk-icon-size: \($0)px;"] } ?? []
    }

    /// The size of a dropdown's or menu button's arrow for `size` (an arrow node: libadwaita
    /// gives it a 16 px icon size and minimum size, and GTK takes the larger); none for 16 px.
    static func arrow(_ size: BaseModifiers.ControlSizeName?) -> [String] {
        iconSize(size).map { ["-gtk-icon-size: \($0)px;", "min-width: \($0)px;", "min-height: \($0)px;"] } ?? []
    }

    /// A text entry's height and side padding for `size`: 26 and 30 px for mini and small (macOS's
    /// 19 and 21 points against 24); none from regular up.
    static func entry(_ size: BaseModifiers.ControlSizeName?) -> [String] {
        switch size {
        case .mini?: return ["min-height: 26px;", "padding: 0 6px;"]
        case .small?: return ["min-height: 30px;", "padding: 0 7px;"]
        case .regular?, .large?, .extraLarge?, nil: return []
        }
    }

    /// A segmented control's group padding and its toggles' height and side padding for `size`,
    /// so the group is as tall as a button of that size; none for regular.
    static func toggleGroup(_ size: BaseModifiers.ControlSizeName?) -> (group: [String], toggle: [String]) {
        guard let (_, _, scale) = boxMetrics(size) else { return ([], []) }
        let (padding, toggle): (Int, Int)
        switch size {
        case .mini?: (padding, toggle) = (2, 14)
        case .small?: (padding, toggle) = (3, 22)
        case .large?: (padding, toggle) = (3, 34)
        case .extraLarge?, .regular?, nil: (padding, toggle) = (4, 44)
        }
        return (["padding: \(padding)px;"], ["min-height: \(toggle)px;", "padding: 0 \(Int((8 * scale).rounded()))px;"])
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
