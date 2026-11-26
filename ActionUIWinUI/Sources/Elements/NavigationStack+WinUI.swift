// Sources/Elements/NavigationStack+WinUI.swift
/*
 NavigationStack on WinUI: the screen on top (the content, or the last screen pushed) under a header
 row, as a Windows app shows a page under its back button and title: WinUI's back button (the one
 NavigationView shows) when a screen is pushed, and the screen's title in the type ramp's Subtitle
 (20 semibold). The title is the screen's navigationTitle, from any of its views (ScreenTitle, shared
 with Linux); the root's falls back to the stack's own. A root screen without a title or toolbar items
 has no header. Less-trusted content titles nothing (the trust policy's .windowTitle, as on Apple and
 Linux): its screens' titles and its stack's own are left out, as if the screen had none.
 The stack fills what it is offered, as SwiftUI's does; its page is clipped to its area, so a screen
 taller than its room is cut at the header rather than drawn over the back button.

 What is pushed, as on Apple and Linux:
 - states["navigationPath"], [Int]: the destinations pushed, by id, from "destinations". Writing it
   pushes or pops; the back button writes it.
 - A NavigationLink with destinationViewId pushes that destination; one with an inline
   "destination" pushes that view, which is not in the path, as SwiftUI's view-destination link is
   not (NavigationLink+WinUI.swift).
 - The selectable-list pattern: when the content is a List with an actionID whose children have
   destinationViewId, choosing a child makes the path that destination (after the List's own
   selection and action), and going back to the root clears the List's selection.

 The screens below the top keep their WinUI objects (their text, their scroll position) out of the
 window until shown again, as SwiftUI keeps them; a screen popped leaves the tree.

 Toolbars: the toolbar items of the views on the top screen show in the header row (NodeToolbar):
 leading items after the back button, principal items in the title's place, trailing items at the
 row's trailing edge, secondaryAction items in a "see more" button's flyout after them, bottomBar
 items in a row below the page. The stack's persistentToolbar (and its toolbar, the deprecated alias)
 shows on every screen at the outer edge: its leading items first, its trailing ones last. A screen
 below the top keeps its items for when it is shown again. A header with items but no title or back
 button shows the items alone. The back button and the items widen the stack to fit them all, where
 SwiftUI's toolbar moves the items that do not fit into an overflow menu (this header has none); the
 title does not, and is cut before the trailing items.

 Not yet: the window's title; the slide of a push and a pop (the screens switch at once); going back
 with Alt+Left or the mouse's back button; the title as a heading for accessibility tools; searchable;
 persistentToolbar items inserted or removed at run time (the persistent toolbar is made from the
 stack's first sync); a screen's toolbar items appear one main-queue turn after the screen is first
 shown (its views sync after the stack).
*/

import CWinUI
import Dispatch

/// One screen above the root: its element, and the destination id when it came from the path.
struct NavigationEntry {
    let element: any ActionUIElementBase
    let destinationID: Int?
}

/// What the header row and the bottom row show besides the back button and the title: the top screen's
/// toolbar items and the stack's persistent ones, by place.
struct NavigationBarItems {
    var leading: [WinUIObject] = []
    var principal: [WinUIObject] = []
    var trailing: [WinUIObject] = []
    var overflow: [WinUIObject] = []
    var bottom: [WinUIObject] = []
}

/// A NavigationStack's header row (its back button, title and toolbar items) above its page, and a
/// bottom row of bottomBar items below it.
@MainActor
final class NavigationStackLayout {
    let panel: LayoutPanel
    let back: WinUIObject
    let title: WinUIObject
    let page: ZStackLayout
    private let bottom: CommandRow
    /// The overflow items' panel, the flyout's content, and the button that opens it.
    private let overflow: StackLayout
    private(set) var overflowButton: WinUIObject?
    /// The header's parts from its leading edge (the back button, leading items, the title or the
    /// principal items) and those at its trailing edge (trailing items, the overflow button).
    private(set) var leadingParts: [WinUIObject] = []
    private(set) var trailingParts: [WinUIObject] = []
    private var overflowItems: [WinUIObject] = []
    /// Whether the header starts with principal items (no back button, no leading items before them).
    private var principalFirstFlag = false
    private var bottomItems: [WinUIObject] = []
    /// The parts' sizes and the page's and the bottom row's from the last measure pass, for arrange.
    private var sizes: [ObjectIdentifier: ActionUIWinUISize] = [:]
    private var measuredPage = ActionUIWinUISize(width: 0, height: 0)
    private var measuredBottom = ActionUIWinUISize(width: 0, height: 0)
    /// The page's clip as last set: a screen taller than its room is cut at the header, as a
    /// Windows page is cut to its area, rather than drawn over the back button.
    private var clippedPage = ActionUIWinUISize(width: -1, height: -1)
    /// Whether the whole layout, header included, is cut at its own edges (a NavigationSplitView's
    /// column: a header too narrow for its items does not draw over the next column).
    var clipsToBounds = false
    private var clippedSelf = ActionUIWinUISize(width: -1, height: -1)

    /// Around the header's parts, and between the back button and the title.
    static let headerInset = 4.0
    static let titleGap = 8.0
    /// The title's leading edge when there is nothing before it.
    static let titleInset = 12.0
    /// Between toolbar items, and from the row's sides to the first one.
    static let itemSpacing = 8.0

    init(back: WinUIObject, title: WinUIObject) throws(WinUIError) {
        panel = try LayoutPanel()
        self.back = back
        self.title = title
        page = try ZStackLayout()
        bottom = try CommandRow()
        overflow = try StackLayout(axis: .vertical)
        overflow.alignment = .start
        try panel.append(page.panel.object)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows the back button, the title and `items` (out of the panel, a part takes no keyboard focus
    /// and accessibility tools do not see it). Principal items take the title's place.
    func setHeader(back showsBack: Bool, title showsTitle: Bool, items: NavigationBarItems) throws(WinUIError) {
        if !items.overflow.isEmpty, overflowButton == nil {
            overflowButton = WinUIObject(adopting: actionUIWinUIOverflowButtonCreate(overflow.panel.object.pointer))
            if overflowButton == nil {
                ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("making the overflow button"))", .error)
            }
        }
        let leading = (showsBack ? [back] : []) + items.leading + (items.principal.isEmpty ? (showsTitle ? [title] : []) : items.principal)
        principalFirstFlag = !showsBack && items.leading.isEmpty && !items.principal.isEmpty
        let trailing = items.trailing + (items.overflow.isEmpty ? [] : overflowButton.map { [$0] } ?? [])
        let headerChanged = !leading.elementsEqual(leadingParts, by: ===) || !trailing.elementsEqual(trailingParts, by: ===)
        let overflowChanged = !items.overflow.elementsEqual(overflowItems, by: ===)
        let bottomChanged = !items.bottom.elementsEqual(bottomItems, by: ===)
        guard headerChanged || overflowChanged || bottomChanged else { return }
        // The parts the old and the new header start with stay in the panel: a part taken out loses
        // keyboard focus, and the back button keeps it across a push or a pop to a screen with other
        // toolbar items. Those after them are taken out and put back.
        let oldParts = leadingParts + trailingParts
        let newParts = leading + trailing
        let keptParts = zip(oldParts, newParts).prefix { $0 === $1 }.count
        // An item whose place changed moves to another panel, and WinUI refuses an element that is
        // still another panel's child: every place whose items change is emptied before any is filled.
        if overflowChanged {
            overflow.setItems([])
        }
        if bottomChanged {
            bottom.setItems(leading: [], principal: [], trailing: [])
            if let index = panel.children.firstIndex(where: { $0 === bottom.panel.object }) {
                try panel.remove(at: index)
            }
        }
        if headerChanged {
            for part in oldParts[keptParts...] {
                if let index = panel.children.firstIndex(where: { $0 === part }) {
                    try panel.remove(at: index)
                }
            }
        }
        leadingParts = leading
        trailingParts = trailing
        overflowItems = items.overflow
        bottomItems = items.bottom
        if overflowChanged {
            overflow.setItems(items.overflow.map { StackLayout.Item(view: $0, spacerMinimum: nil) })
        }
        if headerChanged {
            // Before the page, in reading order, so keyboard focus reaches the header first.
            for (offset, part) in newParts[keptParts...].enumerated() {
                try panel.insert(part, at: keptParts + offset)
            }
        }
        if bottomChanged, !items.bottom.isEmpty {
            bottom.setItems(leading: [], principal: items.bottom, trailing: [])
            try panel.append(bottom.panel.object)
        }
        panel.invalidateLayout()
    }

    private var showsBack: Bool { leadingParts.first === back }
    private var showsBottom: Bool { !bottomItems.isEmpty }

    private func size(_ part: WinUIObject) -> ActionUIWinUISize {
        sizes[ObjectIdentifier(part)] ?? ActionUIWinUISize(width: 0, height: 0)
    }

    /// The header row's least height, also when it shows nothing (a NavigationSplitView's columns keep
    /// one row height); 0: none.
    var headerMinimum = 0.0 {
        didSet {
            if headerMinimum != oldValue {
                panel.invalidateLayout()
            }
        }
    }

    /// The header row's height: its tallest part and the insets, at least headerMinimum; 0 without a
    /// header.
    private var headerHeight: Double {
        let parts = leadingParts + trailingParts
        guard !parts.isEmpty || headerMinimum > 0 else { return 0 }
        return max(parts.reduce(0) { max($0, size($1).height) } + 2 * Self.headerInset, headerMinimum)
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let unbounded = ActionUIWinUISize(width: .infinity, height: .infinity)
        sizes = [:]
        for part in leadingParts + trailingParts {
            sizes[ObjectIdentifier(part)] = part === title ? part.measure(unbounded) : part.measureRequested(unbounded)
        }
        let header = headerHeight
        measuredBottom = showsBottom ? bottom.panel.object.measureRequested(ActionUIWinUISize(width: available.width, height: .infinity))
                                     : ActionUIWinUISize(width: 0, height: 0)
        // The back button and the toolbar items widen the stack, so they never overlap: SwiftUI's toolbar
        // moves the items that do not fit into an overflow menu, and this header has none. The title does
        // not: it is cut before the trailing items, as in SwiftUI. The spacing is arrange's. A split view's
        // column takes the width the split view gives it: there its header is cut at the column's edge,
        // rather than its page laid out wider than the column (WinUI arranges at least the width asked
        // for) and cut. Measured with unbounded width (the split view's own size), it still fits the header.
        let headerWidth = clipsToBounds && available.width.isFinite ? 0 : minimumHeaderWidth()
        let rows = header + measuredBottom.height
        let room = ActionUIWinUISize(width: available.width,
                                     height: available.height.isFinite ? max(available.height - rows, 0) : .infinity)
        measuredPage = page.panel.object.measureRequested(room)
        return ActionUIWinUISize(width: max(headerWidth, measuredPage.width), height: rows + measuredPage.height)
    }

    /// The narrowest header that shows the back button and every toolbar item without overlapping, as
    /// arrange places them, with the title cut to nothing; 0 for a header with neither.
    private func minimumHeaderWidth() -> Double {
        let leading = leadingParts.filter { $0 !== title }
        guard !leading.isEmpty || !trailingParts.isEmpty else { return 0 }
        let principalFirst = leadingParts.first === title || (!leadingParts.isEmpty && leadingParts.first !== back && principalFirstFlag)
        var width = leadingParts.first === back ? Self.headerInset : principalFirst ? Self.titleInset : Self.itemSpacing
        for part in leading {
            width += size(part).width + (part === back ? Self.titleGap : Self.itemSpacing)
        }
        if trailingParts.isEmpty {
            // No gap for a title cut to nothing after the last part: the row's edge is as far from it as
            // the leading edge is from the first part (4 from the back button, 8 from an item).
            width += leading.last === back ? Self.headerInset - Self.titleGap : 0
        } else {
            width += trailingParts.reduce(0) { $0 + size($1).width } + Self.itemSpacing * Double(trailingParts.count)
        }
        return width.rounded(.up)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let header = headerHeight
        func place(_ part: WinUIObject, x: Double, width: Double? = nil) {
            let size = size(part)
            part.arrange(ActionUIWinUIRect(x: x.rounded(.down), y: ((header - size.height) / 2).rounded(.down),
                                           width: width ?? size.width, height: size.height))
        }
        // The trailing parts from the trailing edge.
        let trailingWidth = trailingParts.reduce(0) { $0 + size($1).width } + Self.itemSpacing * Double(max(trailingParts.count - 1, 0))
        let trailingStart = finalSize.width - Self.itemSpacing - trailingWidth
        var x = trailingStart
        for part in trailingParts {
            place(part, x: x)
            x += size(part).width + Self.itemSpacing
        }
        // The leading parts from the leading edge: the back button 4 in, a title alone 12 in, items 8 in.
        let limit = trailingParts.isEmpty ? finalSize.width - Self.headerInset : trailingStart - Self.itemSpacing
        // A title or principal items with nothing before them start 12 in.
        let principalFirst = leadingParts.first === title || (!leadingParts.isEmpty && leadingParts.first !== back && principalFirstFlag)
        x = leadingParts.first === back ? Self.headerInset : principalFirst ? Self.titleInset : Self.itemSpacing
        for part in leadingParts {
            if part === title {
                // Cut before the trailing items when the row is narrower than the title.
                place(part, x: x, width: max(min(size(part).width, limit - x), 0))
            } else {
                place(part, x: x)
            }
            x += size(part).width + (part === back ? Self.titleGap : Self.itemSpacing)
        }
        let pageSize = ActionUIWinUISize(width: finalSize.width, height: max(finalSize.height - header - measuredBottom.height, 0))
        page.panel.object.arrange(ActionUIWinUIRect(x: 0, y: header, width: pageSize.width, height: pageSize.height))
        if pageSize.width != clippedPage.width || pageSize.height != clippedPage.height {
            if actionUIWinUIElementSetClipSize(page.panel.object.pointer, pageSize.width, pageSize.height) {
                clippedPage = pageSize
            } else {
                ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("clipping the page"))", .error)
            }
        }
        if showsBottom {
            bottom.panel.object.arrange(ActionUIWinUIRect(x: 0, y: header + pageSize.height, width: finalSize.width,
                                                          height: measuredBottom.height))
        }
        if clipsToBounds, finalSize.width != clippedSelf.width || finalSize.height != clippedSelf.height {
            if actionUIWinUIElementSetClipSize(panel.object.pointer, finalSize.width, finalSize.height) {
                clippedSelf = finalSize
            } else {
                ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("clipping a column"))", .error)
            }
        }
    }
}

/// The toolbar items of one screen of a NavigationStack (the views on it), or the stack's persistent
/// ones: each toolbar's, in the order the toolbars registered. A change asks the stack to show its
/// header again.
@MainActor
final class NavigationScreenBar: ToolbarBar {
    private weak var stack: RenderNode?
    private var owners: [(owner: ObjectIdentifier, items: [(slot: ToolbarSlot, view: WinUIObject)])] = []

    init(stack: RenderNode) {
        self.stack = stack
    }

    func set(owner: ObjectIdentifier, items: [(slot: ToolbarSlot, view: WinUIObject)]) {
        if let index = owners.firstIndex(where: { $0.owner == owner }) {
            guard !owners[index].items.elementsEqual(items, by: { $0.slot == $1.slot && $0.view === $1.view }) else { return }
            owners[index].items = items
        } else {
            owners.append((owner, items))
        }
        changed()
    }

    func remove(owner: ObjectIdentifier) {
        guard owners.contains(where: { $0.owner == owner }) else { return }
        owners.removeAll { $0.owner == owner }
        changed()
    }

    private func changed() {
        if let stack, stack.isAttached {
            SyncScheduler.shared.markDirty(stack)
        }
    }

    /// The items in `slot`, in order.
    func views(_ slot: ToolbarSlot) -> [WinUIObject] {
        owners.flatMap(\.items).filter { $0.slot == slot }.map(\.view)
    }
}

/// What a NavigationStack shows: its layout and the screens pushed above the root.
@MainActor
final class NavigationStackState {
    let layout: NavigationStackLayout
    /// The screens above the root, in order.
    var entries: [NavigationEntry] = []
    /// The title last given to the title block.
    var shownTitle: String?
    /// Each screen's toolbar items, by the screen's node; the stack's persistent toolbar and its items.
    private var screenBars: [ObjectIdentifier: (screen: RenderNode, bar: NavigationScreenBar)] = [:]
    private(set) var persistentBar: NavigationScreenBar?
    var persistentToolbar: NodeToolbar?

    init(layout: NavigationStackLayout) {
        self.layout = layout
    }

    /// The bar of `screen` (the content's node or a pushed screen's) of the stack `stack`.
    func screenBar(for screen: RenderNode, stack: RenderNode) -> NavigationScreenBar {
        if let existing = screenBars[ObjectIdentifier(screen)] {
            return existing.bar
        }
        let bar = NavigationScreenBar(stack: stack)
        screenBars[ObjectIdentifier(screen)] = (screen, bar)
        return bar
    }

    func persistentBar(stack: RenderNode) -> NavigationScreenBar {
        if let persistentBar {
            return persistentBar
        }
        let bar = NavigationScreenBar(stack: stack)
        persistentBar = bar
        return bar
    }

    /// The bar of the screen `screen` shows, nil when none of its views declares a toolbar.
    func existingBar(for screen: RenderNode) -> NavigationScreenBar? {
        screenBars[ObjectIdentifier(screen)]?.bar
    }

    /// Lets go of the bars of screens that left the stack.
    func dropBars(keeping screens: [RenderNode]) {
        let kept = Set(screens.map(ObjectIdentifier.init))
        screenBars = screenBars.filter { kept.contains($0.key) && $0.value.screen.isAttached }
    }

    /// The destination ids of the entries: what the path should hold.
    var path: [Int] { entries.compactMap(\.destinationID) }
}

extension NavigationStack: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    /// As its screens can be made smaller (a ScrollView screen in a column), as a TabView's.
    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let back = WinUIObject(adopting: actionUIWinUIBackButtonCreate()) else {
            throw WinUIError.last("creating a NavigationStack's back button")
        }
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a NavigationStack's title")
        }
        // The type ramp's Subtitle, as a page's title.
        if !actionUIWinUIElementSetFont(title.pointer, nil, 20, 600) {
            ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("setting the title's font"))", .error)
        }
        let state = NavigationStackState(layout: try NavigationStackLayout(back: back, title: title))
        node.state = state
        WinUIEvents.connect(back, actionUIWinUIButtonOnClick, "a NavigationStack's back button") { [weak node] in
            guard let node, node.isAttached else { return }
            userWentBack(node)
        }
        return state.layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? NavigationStackState else { return }
        let layout = state.layout
        let element = node.effectiveElement
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []

        // A path the host wrote (or a destination link pushed) rebuilds the entries from it; one that
        // already matches keeps the inline screens among them.
        let path = node.model.states["navigationPath"] as? [Int] ?? []
        if path != state.path {
            // Back at the root of a selectable list by the host's path: as by the back button. The
            // write waits a turn: an update does not write the model.
            if path.isEmpty, !state.entries.isEmpty, let list = selectableList(node) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if list.isAttached, !(list.model.value as? [String] ?? []).isEmpty {
                            list.model.value = [] as [String]
                        }
                    }
                }
            }
            state.entries = path.compactMap { id in
                guard let destination = destinations.first(where: { $0.id == id }) else {
                    ActionUIModel.shared.logger.log("NavigationStack \(node.element.id): no destination \(id)", .warning)
                    return nil
                }
                return NavigationEntry(element: destination, destinationID: id)
            }
        }
        // A screen shown twice would be one node: the first stays, later ones are dropped.
        var seen = Set<Int>()
        state.entries = state.entries.filter { seen.insert($0.element.id).inserted && $0.element.id != content?.id }

        var screens: [any ActionUIElementBase] = content.map { [$0] } ?? []
        screens += state.entries.map(\.element)
        let nodes = node.syncChildren(screens)
        let top = nodes.last
        state.dropBars(keeping: nodes)

        // The stack's persistent toolbar (and its toolbar, the deprecated alias): on every screen, at
        // the outer edge of the bar.
        let persistentItems = ToolbarHelper.persistentToolbarItems(of: element)
        if state.persistentToolbar == nil, !persistentItems.isEmpty {
            state.persistentToolbar = NodeToolbar.persistent(for: node, items: persistentItems)
        }
        state.persistentToolbar?.update()
        let screenBar = top.flatMap { state.existingBar(for: $0) }
        let persistent = state.persistentBar
        var items = NavigationBarItems()
        items.leading = (persistent?.views(.leading) ?? []) + (screenBar?.views(.leading) ?? [])
        items.principal = screenBar?.views(.principal) ?? []
        if items.principal.isEmpty {
            items.principal = persistent?.views(.principal) ?? []
        }
        items.trailing = (screenBar?.views(.trailing) ?? []) + (persistent?.views(.trailing) ?? [])
        items.overflow = (screenBar?.views(.overflow) ?? []) + (persistent?.views(.overflow) ?? [])
        items.bottom = (screenBar?.views(.bottom) ?? []) + (persistent?.views(.bottom) ?? [])

        // The top screen's title; the root's falls back to the stack's own. An empty title is none.
        var title = top.flatMap { ScreenTitle.find(in: $0.element, windowModel: node.windowModel) }
        // Less-trusted content's stack does not title its screens, as ScreenTitle refuses its views'.
        if title == nil, state.entries.isEmpty, let own = BaseModifiers(node.properties).navigationTitle, !own.isEmpty,
           LinkTrust.allowsLoggingOnce(.windowTitle, what: "setting the title", node) {
            title = own
        }
        if let title, title != state.shownTitle {
            if actionUIWinUITextBlockSetText(layout.title.pointer, title) {
                state.shownTitle = title
                layout.panel.invalidateLayout()
            } else {
                ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("showing the title"))", .error)
            }
        }
        do {
            try layout.setHeader(back: !state.entries.isEmpty, title: title != nil, items: items)
        } catch {
            ActionUIModel.shared.logger.log("NavigationStack: \(error)", .error)
        }
        // RenderNode enables the view, which is the layout's panel (no Control): the button is enabled here.
        if !actionUIWinUIElementSetEnabled(layout.back.pointer, !(node.isDisabled || node.isHidden)) {
            ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("enabling the back button"))", .error)
        }
        node.applyAccessibilityHidden(to: layout.back)
        node.applyAccessibilityHidden(to: layout.title)
        // The overflow button too, as the back button (the items in its flyout follow their own nodes).
        if let overflowButton = layout.overflowButton {
            if !actionUIWinUIElementSetEnabled(overflowButton.pointer, !(node.isDisabled || node.isHidden)) {
                ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("enabling the overflow button"))", .error)
            }
            node.applyAccessibilityHidden(to: overflowButton)
        }

        layout.page.setItems(top.flatMap { screen in
            screen.outerView.map { [ZStackLayout.Item(view: $0, expansion: screen.expansion, cap: screen.caps)] }
        } ?? [])
    }

    // MARK: Navigating

    /// The back button: the top screen is popped, and the path follows.
    private static func userWentBack(_ node: RenderNode) {
        guard let state = node.state as? NavigationStackState, !state.entries.isEmpty else { return }
        state.entries.removeLast()
        if (node.model.states["navigationPath"] as? [Int] ?? []) != state.path {
            node.model.states["navigationPath"] = state.path
        }
        // Back at the root of a selectable list: its selection clears, so the same row can be chosen again.
        if state.entries.isEmpty, let list = selectableList(node) {
            list.model.value = [] as [String]
        }
        SyncScheduler.shared.markDirty(node)
    }

    /// Pushes `element` (a NavigationLink's inline destination, not in the path) on the stack
    /// `node` is in, or the destination `destinationID` from its "destinations".
    static func push(from node: RenderNode, element: (any ActionUIElementBase)?, destinationID: Int?) {
        guard let stack = enclosingStack(node), let state = stack.state as? NavigationStackState else {
            ActionUIModel.shared.logger.log("NavigationLink \(node.element.id) is not in a NavigationStack", .warning)
            return
        }
        let entry: NavigationEntry
        if let element {
            entry = NavigationEntry(element: element, destinationID: nil)
        } else if let destinationID {
            let destinations = stack.effectiveElement.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
            guard let destination = destinations.first(where: { $0.id == destinationID }) else {
                ActionUIModel.shared.logger.log("NavigationStack \(stack.element.id): no destination \(destinationID)", .warning)
                return
            }
            entry = NavigationEntry(element: destination, destinationID: destinationID)
        } else {
            return
        }
        // A screen already shown (a double click's second click) is not pushed again: one node per
        // screen, and the path keeps naming what is shown.
        guard !state.entries.contains(where: { $0.element.id == entry.element.id }) else { return }
        state.entries.append(entry)
        if entry.destinationID != nil {
            stack.model.states["navigationPath"] = state.path
        } else {
            SyncScheduler.shared.markDirty(stack)
        }
    }

    /// The selectable-list pattern: the user chose `childID` in `list`, the stack's content; when
    /// the child names a destination, the path becomes it, after the List's own selection and
    /// action (which wait one main-queue turn).
    static func contentListChose(_ list: RenderNode, childID: Int?) {
        guard let childID, let stack = list.parent, stack.element.type == "NavigationStack",
              selectableList(stack) === list,
              let child = list.windowModel.viewModels[childID],
              let destinationID = BaseModifiers(child.properties).destinationViewId else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard stack.isAttached else { return }
                if (stack.model.states["navigationPath"] as? [Int] ?? []) != [destinationID] {
                    stack.model.states["navigationPath"] = [destinationID]
                }
            }
        }
    }

    /// The stack's content node when it is a List with an actionID and destinations to choose.
    private static func selectableList(_ stack: RenderNode) -> RenderNode? {
        guard let content = stack.effectiveElement.subviews?["content"] as? any ActionUIElementBase,
              content.type == "List", let list = stack.orderedChildren.first(where: { $0.element.id == content.id }),
              List.Props(list.properties).actionID != nil,
              !(stack.effectiveElement.subviews?["destinations"] as? [any ActionUIElementBase] ?? []).isEmpty else { return nil }
        return list
    }

    /// The nearest NavigationStack node above `node`.
    private static func enclosingStack(_ node: RenderNode) -> RenderNode? {
        var current = node.parent
        while let candidate = current {
            if candidate.element.type == "NavigationStack" {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }
}
