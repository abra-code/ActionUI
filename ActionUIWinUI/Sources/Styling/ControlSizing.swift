// Sources/Styling/ControlSizing.swift
/*
 SwiftUI's controlSize on WinUI: what makes a control mini, small, large or extra large. Regular is
 WinUI's own size (its button and combo box are 32 pixels tall where macOS's button is 24 points), and
 the other sizes keep macOS's proportions to it, as the Linux renderer does on GNOME (measured on
 macOS 27):

   size        height       side padding  label font
   mini        13 (0.54)    8 (0.67)       9 (0.69)
   small       20 (0.83)   10 (0.83)      11 (0.85)
   regular     24          12             13
   large       28 (1.17)   14 (1.17)      13
   extraLarge  36 (1.5)    18 (1.5)       13

 so a WinUI button is about 17, 27, 32, 37 and 48 pixels tall, with a 10, 12, 14, 14 and 14 pixel
 label. The label's font scales only where no font is given: a control with a font of its own, or
 one from a container, keeps it, as on Linux and as a SwiftUI button's label does on iOS (a bordered
 button on macOS draws its title in the control size's font whatever its font). Only the box grows for large and extra
 large: its height, its side padding, its label centered; for mini and small the top and bottom
 padding shrink so the label fits.

 Where it applies: a Button (its label, its icon, and its box unless it is plain, which is its label
 alone, as on Apple and Linux); a Picker's choice (its title keeps its font, as on macOS), with a menu
 Picker's combo box sized as a button. A segmented or radio group Picker takes the label font only.
*/

import CWinUI

@MainActor
enum ControlSizing {
    /// WinUI's body text size, the label font of a regular control.
    static let regularFontSize = 14.0

    /// A WinUI control's regular box: its height and padding (WinUI 3's theme resources).
    struct RegularBox {
        let height: Double
        let left: Double, top: Double, right: Double, bottom: Double
    }

    /// The standard button (ButtonPadding 11,5,11,6).
    static let button = RegularBox(height: 32, left: 11, top: 5, right: 11, bottom: 6)
    /// The combo box (32 tall from its template's dropdown glyph, whose MinHeight is ComboBoxMinHeight;
    /// ComboBoxPadding 12,5,0,7; the glyph has a column of its own).
    static let comboBox = RegularBox(height: 32, left: 12, top: 5, right: 0, bottom: 7)

    /// A box for a control size: its minimum height and padding.
    struct Box: Equatable {
        let minHeight: Double
        let left: Double, top: Double, right: Double, bottom: Double
    }

    /// macOS's proportions of `size` to regular: the height, the side padding and the label font
    /// (nil: regular's); nil for regular and for no size.
    static func ratios(_ size: BaseModifiers.ControlSizeName?) -> (height: Double, side: Double, font: Double?)? {
        switch size {
        case .mini?: return (0.54, 0.67, 0.69)
        case .small?: return (0.83, 0.83, 0.85)
        case .large?: return (1.17, 1.17, nil)
        case .extraLarge?: return (1.5, 1.5, nil)
        case .regular?, nil: return nil
        }
    }

    /// The text appearance of `node`'s control label: its own, with the control size's font when it
    /// has none (neither its own nor a container's).
    static func appearance(_ node: RenderNode) -> TextAppearance {
        var appearance = node.textAppearance
        guard appearance.font == nil, let scale = ratios(node.controlSize)?.font else { return appearance }
        appearance.font = .sized(name: nil, size: (regularFontSize * scale).rounded(), weight: nil, design: .default)
        return appearance
    }

    /// The box of a control whose regular box is `regular` for `node`'s control size, with its label
    /// in `appearance`; nil for regular (the control's own).
    static func box(_ regular: RegularBox, _ node: RenderNode, appearance: TextAppearance) -> Box? {
        guard let ratios = ratios(node.controlSize) else { return nil }
        let height = (regular.height * ratios.height).rounded()
        let fontSize = TextAppearance.winUIFont(appearance.font).size
        // Segoe UI's line is about 1.33 times its size; a 1-pixel border above and below.
        let line = ((fontSize > 0 ? fontSize : regularFontSize) * 1.33).rounded(.up)
        let room = max(0, height - line - 2)
        let vertical = regular.top + regular.bottom
        // The top and bottom padding shrink to fit a smaller box (in their own proportion), and
        // stay for a larger one, whose minimum height centers the label.
        let scale = room < vertical ? room / vertical : 1
        return Box(minHeight: height,
                   left: (regular.left * ratios.side).rounded(), top: (regular.top * scale).rounded(.down),
                   right: (regular.right * ratios.side).rounded(), bottom: (regular.bottom * scale).rounded(.down))
    }

    /// Gives `control` `box` (nil: its own minimum height and padding again); `what` names it in a log line.
    static func apply(_ box: Box?, to control: WinUIObject, what: String) {
        let applied = box.map { actionUIWinUIControlSetBox(control.pointer, $0.minHeight, $0.left, $0.top, $0.right, $0.bottom) }
            ?? actionUIWinUIControlSetBox(control.pointer, -1, 0, 0, 0, 0)
        if !applied {
            ActionUIModel.shared.logger.log("ControlSizing: \(WinUIError.last("sizing \(what)"))", .error)
        }
    }
}
