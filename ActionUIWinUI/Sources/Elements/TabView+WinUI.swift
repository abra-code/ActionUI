// Sources/Elements/TabView+WinUI.swift
/*
 TabView on WinUI: a SelectorBar of the tabs above the selected tab's page, as macOS puts its tab
 buttons above the page and as the Linux renderer does. The SelectorBar is the Windows App SDK's
 control for switching between views of the same content (a Picker's segmented style uses it too); a
 WinUI TabView is a document's tabs, closed and reordered by the user, which a SwiftUI TabView is not.

 - Each child is a Tab: its title and its systemImage's symbol label the tab's item (an item without
   a symbol, or with a name that has no Windows symbol, shows its title alone); its "content" is the
   page. The bar is centered above the page, at its own width, as macOS centers its tab buttons.
 - The page is the selected tab's content, laid out as a ZStack's one child: centered at its own
   size, filling the room in an axis it expands in. The other tabs' contents keep their WinUI objects
   (their text, their scroll position) out of the window until chosen again, as SwiftUI keeps a tab's
   state.
 - The TabView fills what it is offered, as SwiftUI's does.
 - The value, as on Apple, is the selected tab's index (initially the selection property); out of
   range, the first tab is shown. The user's choice stores it and fires actionID with the index as
   context; a host's write switches. The bar also reports the renderer's own selection, which the
   handler ignores (the index the renderer last selected).
 - style: every style looks the same here.

 Not yet: badge (a SelectorBarItem has no badge); assetImage (an image file or asset as a tab's
 icon); a tab's title as text appearance (the bar keeps the system's font).
*/

import CWinUI

/// A TabView's bar above its page.
@MainActor
final class TabViewLayout {
    let panel: LayoutPanel
    let bar: WinUIObject
    let page: ZStackLayout
    /// The bar's and the page's sizes from the last measure pass, for arrange.
    private var measuredBar = ActionUIWinUISize(width: 0, height: 0)
    private var measuredPage = ActionUIWinUISize(width: 0, height: 0)

    init(bar: WinUIObject) throws(WinUIError) {
        panel = try LayoutPanel()
        self.bar = bar
        page = try ZStackLayout()
        try panel.append(bar)
        try panel.append(page.panel.object)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        measuredBar = bar.measure(ActionUIWinUISize(width: available.width, height: .infinity))
        let room = ActionUIWinUISize(width: available.width,
                                     height: available.height.isFinite ? max(available.height - measuredBar.height, 0) : .infinity)
        measuredPage = page.panel.object.measureRequested(room)
        return ActionUIWinUISize(width: max(measuredBar.width, measuredPage.width), height: measuredBar.height + measuredPage.height)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let barWidth = min(measuredBar.width, finalSize.width)
        bar.arrange(ActionUIWinUIRect(x: ((finalSize.width - barWidth) / 2).rounded(.down), y: 0,
                                      width: barWidth, height: measuredBar.height))
        page.panel.object.arrange(ActionUIWinUIRect(x: 0, y: measuredBar.height, width: finalSize.width,
                                                     height: max(finalSize.height - measuredBar.height, 0)))
    }
}

/// A TabView's layout and what its bar shows.
@MainActor
final class TabViewState {
    let layout: TabViewLayout
    /// The items' titles and symbol names, in order, as last given to the bar.
    var titles: [String]?
    var symbols: [String?] = []
    /// The index the renderer last selected: a selection event reporting it is the renderer's own.
    var shownIndex = -1

    init(layout: TabViewLayout) {
        self.layout = layout
    }
}

extension TabView: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { [.horizontal, .vertical] }

    /// As its contents can be made smaller (a ScrollView page in a column), as a GroupBox's or a
    /// ZStack's: a stack measures it for the room it gives, not for its page's whole length.
    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let bar = WinUIObject(adopting: actionUIWinUIChoiceCreate(ActionUIWinUIChoiceSegments)) else {
            throw WinUIError.last("creating a TabView's bar")
        }
        let state = TabViewState(layout: try TabViewLayout(bar: bar))
        node.state = state
        WinUIEvents.connect(bar, actionUIWinUIChoiceOnSelectionChanged, "a TabView's selection") { [weak node, weak state, weak bar] in
            guard let node, let state, let bar, node.isAttached else { return }
            let index = Int(actionUIWinUIChoiceGetSelectedIndex(bar.pointer))
            // None selected (the items rebuilt): the next choice of any tab is the user's.
            guard index >= 0 else {
                state.shownIndex = -1
                return
            }
            guard index != state.shownIndex else { return }
            state.shownIndex = index
            node.model.value = index
            if let actionID = Props(node.properties).actionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id,
                                                   viewPartID: 0, context: index, origin: LinkTrust.origin(node))
            }
        }
        return state.layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? TabViewState else { return }
        let layout = state.layout
        let tabs = node.effectiveElement.subviews?["children"] as? [any ActionUIElementBase] ?? []
        // Each tab's properties as they are now (a host can change a title).
        let tabProperties = tabs.map { tab in
            node.windowModel.viewModels[tab.id].map { ActionUIRegistry.shared.currentProperties(element: tab, model: $0) } ?? tab.properties
        }
        let titles = tabProperties.enumerated().map { index, properties in properties["title"] as? String ?? "Tab \(index + 1)" }
        let symbols = tabProperties.map { properties -> String? in
            guard let name = properties["systemImage"] as? String, !name.isEmpty else { return nil }
            return name
        }
        if titles != state.titles || symbols != state.symbols {
            let set = Picker.withCStrings(titles) { actionUIWinUIChoiceSetItems(layout.bar.pointer, $0, Int32(titles.count)) }
            if !set {
                ActionUIModel.shared.logger.log("TabView: \(WinUIError.last("setting the tabs"))", .error)
            }
            for (index, name) in symbols.enumerated() where set {
                guard let name, let symbol = ImageLayout.makeSymbol(name) else { continue }
                if !actionUIWinUISymbolSetSize(symbol.pointer, Self.symbolSide)
                    || !actionUIWinUIChoiceSetItemIcon(layout.bar.pointer, Int32(index), symbol.pointer) {
                    ActionUIModel.shared.logger.log("TabView: \(WinUIError.last("showing a tab's symbol"))", .error)
                }
            }
            state.titles = titles
            state.symbols = symbols
            // The items are new: none is selected.
            state.shownIndex = -1
            layout.panel.invalidateLayout()
        }
        // RenderNode enables the view, which is the layout's panel (no Control): the bar is enabled here.
        if !actionUIWinUIElementSetEnabled(layout.bar.pointer, !(node.isDisabled || node.isHidden)) {
            ActionUIModel.shared.logger.log("TabView: \(WinUIError.last("enabling the tabs"))", .error)
        }
        node.applyAccessibilityHidden(to: layout.bar)

        // Every tab's content is a child node; a tab without one shows nothing.
        let contents = tabs.map { $0.subviews?["content"] as? any ActionUIElementBase }
        let nodes = node.syncChildren(contents.compactMap { $0 })

        // The selected tab: the value, else the selection property; out of range, the first.
        let value = initialValue(node.model) as? Int ?? 0
        let index = tabs.indices.contains(value) ? value : (tabs.isEmpty ? -1 : 0)
        if index != state.shownIndex {
            // Before the call, whose event can come at once.
            state.shownIndex = index
            if !actionUIWinUIChoiceSetSelectedIndex(layout.bar.pointer, Int32(index)) {
                ActionUIModel.shared.logger.log("TabView: \(WinUIError.last("selecting a tab"))", .error)
            }
        }
        let selected = index >= 0 ? contents[index].flatMap { content in nodes.first { $0.element.id == content.id } } : nil
        layout.page.setItems(selected.flatMap { child in
            child.outerView.map { [ZStackLayout.Item(view: $0, expansion: child.expansion, cap: child.caps)] }
        } ?? [])
    }

    /// A tab's symbol side: Fluent's 16-pixel icon, the size a SelectorBarItem's icon is drawn at.
    static let symbolSide = 16.0
}
