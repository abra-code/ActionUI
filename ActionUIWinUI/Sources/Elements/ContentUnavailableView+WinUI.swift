// Sources/Elements/ContentUnavailableView+WinUI.swift
/*
 ContentUnavailableView on WinUI: the icon, the title and the description, centered one above the
 other, in the secondary color, as macOS draws them (measured on macOS 27: the icon's outline about
 34 points, 31 above the title's letters, the title and the description about 11 apart, letter to
 letter; the Windows renderings match). As wide as it is offered up to
 400 points, centered in more, and as tall as it needs, with 16 around it, as on Linux.

 - The title is the value, else the title property, in WinUI's Body Large semibold (18); a title
   alone (no icon, no description) is not bold, as macOS draws it. The description is in Body (14).
   Both wrap at words, and inside a word that does not fit, centered.
 - The icon is systemImage's SF Symbol outline (as Image draws it) in a 48-point box; none without one.
 - search: SwiftUI's search variant: a magnifying glass, "No Results" (or "No Results for" the query,
   which is the value, else the query property) and "Check the spelling or try a new search.". The
   title, systemImage and description are not used then, as in SwiftUI.

 Not yet: the search variant's texts are English (SwiftUI localizes them); the 400-point limit is not
 told to stacks (in a row beside an element that fills, it is given half and centers in it, where
 SwiftUI gives it 400); accessible names (the icon left out, as VoiceOver does).
*/

import CWinUI

/// A ContentUnavailableView's layout: the icon, the title and the description in a centered column.
@MainActor final class ContentUnavailableLayout {
    static let iconSide = 48.0
    /// Between the icon's box and the title's line: 31 points from the outline to the title's letters, as
    /// on macOS (measured on both).
    static let iconGap = 17.0
    static let descriptionGap = 6.0
    static let margin = 16.0
    static let maximumWidth = 400.0

    let panel: LayoutPanel
    let title: WinUIObject
    let description: WinUIObject
    private(set) var icon: WinUIObject?
    var iconName: String?
    var shownTitle: String?
    var shownDescription: String?
    private var measured: [ActionUIWinUISize] = []

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()),
              let description = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a ContentUnavailableView's texts")
        }
        self.title = title
        self.description = description
        for text in [title, description] {
            guard actionUIWinUITextBlockSetWraps(text.pointer, true),
                  actionUIWinUITextBlockSetAlignment(text.pointer, ActionUIWinUITextCenter) else {
                throw WinUIError.last("setting up a ContentUnavailableView's text")
            }
            try panel.append(text)
        }
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows the symbol `name` (nil: no icon).
    func setIcon(_ name: String?) {
        guard name != iconName else { return }
        iconName = name
        do {
            if icon != nil {
                try panel.remove(at: 0)
                icon = nil
            }
            if let name, let symbol = ImageLayout.makeSymbol(name) {
                if !actionUIWinUISymbolSetSize(symbol.pointer, Self.iconSide) {
                    ActionUIModel.shared.logger.log("ContentUnavailableView: \(WinUIError.last("sizing the icon"))", .error)
                }
                try panel.insert(symbol, at: 0)
                icon = symbol
            }
        } catch {
            ActionUIModel.shared.logger.log("ContentUnavailableView: \(error)", .error)
        }
        panel.invalidateLayout()
    }

    private var hasDescription: Bool { !(shownDescription ?? "").isEmpty }

    /// The parts shown, top to bottom, with the gap above each.
    private var parts: [(object: WinUIObject, gap: Double)] {
        var parts: [(WinUIObject, Double)] = []
        if let icon {
            parts.append((icon, 0))
        }
        parts.append((title, icon == nil ? 0 : Self.iconGap))
        if hasDescription {
            parts.append((description, Self.descriptionGap))
        }
        return parts
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let width = available.width.isFinite ? min(available.width, Self.maximumWidth) : Self.maximumWidth
        let inner = ActionUIWinUISize(width: max(width - 2 * Self.margin, 0), height: .infinity)
        if !hasDescription {
            _ = description.measure(ActionUIWinUISize(width: 0, height: 0))
        }
        measured = parts.map { $0.object.measure(inner) }
        let height = zip(parts, measured).reduce(0) { $0 + $1.0.gap + $1.1.height }
        return ActionUIWinUISize(width: width, height: height + 2 * Self.margin)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        // The column at its width, centered in a wider frame.
        let width = min(finalSize.width, Self.maximumWidth)
        let left = (finalSize.width - width) / 2 + Self.margin
        let inner = max(width - 2 * Self.margin, 0)
        var y = Self.margin
        for (part, size) in zip(parts, measured) {
            y += part.gap
            let x = part.object === icon ? left + (inner - size.width) / 2 : left
            let partWidth = part.object === icon ? size.width : inner
            part.object.arrange(ActionUIWinUIRect(x: x, y: y, width: partWidth, height: size.height))
            y += size.height
        }
        if !hasDescription {
            description.arrange(ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0))
        }
    }
}

extension ContentUnavailableView: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .horizontal }

    /// Narrower than 400 in a row that has less room, its texts wrapping, as SwiftUI's and the Linux
    /// renderer's do (a stack takes an expanding child's own width as its least otherwise).
    static func compression(_ node: RenderNode) -> Expansion { .horizontal }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try ContentUnavailableLayout()
        node.state = layout
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? ContentUnavailableLayout else { return }
        let content = shown(Props(node.properties), node.model.value as? String)
        layout.setIcon(content.icon)
        var ok = true
        if content.title != layout.shownTitle {
            ok = actionUIWinUITextBlockSetText(layout.title.pointer, content.title)
            layout.shownTitle = ok ? content.title : nil
            layout.panel.invalidateLayout()
        }
        let description = content.description ?? ""
        if description != layout.shownDescription {
            let set = actionUIWinUITextBlockSetText(layout.description.pointer, description)
            layout.shownDescription = set ? description : nil
            ok = ok && set
            layout.panel.invalidateLayout()
        }
        // In the secondary color unless a foregroundStyle is in effect; the title bold unless it is alone.
        let alone = content.icon == nil && description.isEmpty
        var appearance = node.textAppearance
        if appearance.foreground == nil {
            appearance.foreground = "secondary"
        }
        let titleSize = 18.0
        let fonts: [(WinUIObject, Double, Int32)] = [(layout.title, titleSize, alone ? 400 : 600), (layout.description, 14, 400)]
        for (text, size, weight) in fonts {
            Paint.apply(Paint.parse(appearance.foreground, role: .foreground, tint: appearance.tint), ActionUIWinUIBrushForeground, to: text, what: "a ContentUnavailableView's text")
            if !actionUIWinUIElementSetFont(text.pointer, nil, size, weight) {
                ok = false
            }
            node.applyAccessibilityHidden(to: text)
        }
        if let icon = layout.icon {
            Paint.apply(Paint.parse(appearance.foreground, role: .foreground, tint: appearance.tint), ActionUIWinUIBrushForeground, to: icon, what: "a ContentUnavailableView's icon")
        }
        if !ok {
            ActionUIModel.shared.logger.log("ContentUnavailableView: \(WinUIError.last("showing the texts"))", .error)
        }
    }

    /// The title, description and symbol shown, from the properties and the value, as on Linux.
    static func shown(_ props: Props, _ value: String?) -> (title: String, description: String?, icon: String?) {
        if props.search {
            let query = value ?? props.query
            let title = query.isEmpty ? "No Results" : "No Results for \u{201C}\(query)\u{201D}"
            return (title, "Check the spelling or try a new search.", "magnifyingglass")
        }
        let icon = props.systemImage.flatMap { $0.isEmpty ? nil : $0 }
        return (value ?? props.title, props.description, icon)
    }
}
