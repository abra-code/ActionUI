// Sources/Elements/Label+WinUI.swift
/*
 Label on WinUI: its icon and its title side by side, 8 apart, each at its own size (IconTitleLayout),
 as SwiftUI's Label on macOS and the Linux renderer lay them out.

 - The title is the value, else the title property (Label.initialValue).
 - The icon is the symbol Image shows for systemImage (ImageLayout.symbolSide), in the label's text
   color; without one, the title alone.

 Not yet: imageName (an image file or asset as the icon).
*/

import CWinUI

extension Label: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try IconTitleLayout()
        node.state = LabelState(layout: layout)
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? LabelState else { return }
        let layout = state.layout
        let props = Props(node.properties)
        layout.setTitle(node.model.value as? String ?? props.title)
        node.applyTextAppearance(to: layout.title, what: "a Label")
        // An empty name is no icon, as on Linux.
        let symbol = props.systemImage.flatMap { $0.isEmpty ? nil : $0 }
        if symbol != state.symbol {
            state.symbol = symbol
            layout.setIcon(symbol.flatMap(ImageLayout.makeSymbol))
        }
        if let icon = layout.icon {
            Paint.apply(Paint.parse(node.textAppearance.foreground, role: .foreground), ActionUIWinUIBrushForeground,
                        to: icon, what: "a Label's symbol")
        }
        layout.setIconSide(ImageLayout.symbolSide(node, scale: nil))
    }
}

/// A Label's layout and the symbol name it shows.
@MainActor final class LabelState {
    let layout: IconTitleLayout
    var symbol: String?

    init(layout: IconTitleLayout) {
        self.layout = layout
    }
}
