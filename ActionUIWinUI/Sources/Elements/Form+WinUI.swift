// Sources/Elements/Form+WinUI.swift
/*
 Form on WinUI: laid out as macOS lays out a Form (its columns style; measured on macOS 27 for the
 Linux renderer): a column of its rows, 8 points apart and aligned to its leading edge, as large as its
 rows unless one of them fills, and centered in its parent like a VStack. A Section's rows are laid out
 as the Form's own (Section+WinUI).

 Not yet: the label column (the titles of its LabeledContent, Picker, Stepper, Toggle, TextField and
 SecureField rows ending at one column as wide as the widest, every row's content starting 8 after it,
 as on Linux); 5 points instead of 8 above a row with text below a row without (measured on macOS).
*/

extension Form: ActionUIWinUIRenderer {
    /// The space between two rows, measured on macOS 27.
    static let rowSpacing = 8.0

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try StackViews.make(node, axis: .vertical)
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let stack = StackViews.stack(of: node) else { return }
        StackViews.configure(stack, spacing: rowSpacing, alignment: .start)
        syncStackContent(node, stack)
    }
}
