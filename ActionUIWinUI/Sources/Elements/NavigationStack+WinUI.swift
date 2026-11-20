// Sources/Elements/NavigationStack+WinUI.swift
/*
 NavigationStack on WinUI: the screen on top (the content, or the last screen pushed) under a header
 row, as a Windows app shows a page under its back button and title: WinUI's back button (the one
 NavigationView shows) when a screen is pushed, and the screen's title in the type ramp's Subtitle
 (20 semibold). The title is the screen's navigationTitle, from any of its views (ScreenTitle, shared
 with Linux); the root's falls back to the stack's own. A root screen without a title has no header.
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

 Not yet: the toolbars (persistentToolbar and the screens' own); the window's title; the slide of a
 push and a pop (the screens switch at once); going back with Alt+Left or the mouse's back button;
 the title as a heading for accessibility tools.
*/

import CWinUI
import Dispatch

/// One screen above the root: its element, and the destination id when it came from the path.
struct NavigationEntry {
    let element: any ActionUIElementBase
    let destinationID: Int?
}

/// A NavigationStack's header row (its back button and title) above its page.
@MainActor
final class NavigationStackLayout {
    let panel: LayoutPanel
    let back: WinUIObject
    let title: WinUIObject
    let page: ZStackLayout
    /// Whether the back button and the title are in the panel.
    private(set) var showsBack = false
    private(set) var showsTitle = false
    /// The parts' sizes from the last measure pass, for arrange.
    private var measuredBack = ActionUIWinUISize(width: 0, height: 0)
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)
    private var measuredPage = ActionUIWinUISize(width: 0, height: 0)
    /// The page's clip as last set: a screen taller than its room is cut at the header, as a
    /// Windows page is cut to its area, rather than drawn over the back button.
    private var clippedPage = ActionUIWinUISize(width: -1, height: -1)

    /// Around the header's parts, and between the back button and the title.
    static let headerInset = 4.0
    static let titleGap = 8.0
    /// The title's leading edge when there is no back button.
    static let titleInset = 12.0

    init(back: WinUIObject, title: WinUIObject) throws(WinUIError) {
        panel = try LayoutPanel()
        self.back = back
        self.title = title
        page = try ZStackLayout()
        try panel.append(page.panel.object)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Puts the back button and the title in the panel, or takes them out (out of the panel, they
    /// take no keyboard focus and accessibility tools do not see them).
    func setHeader(back showsBack: Bool, title showsTitle: Bool) throws(WinUIError) {
        if showsBack != self.showsBack {
            if showsBack {
                try panel.insert(back, at: 0)
            } else if let index = panel.children.firstIndex(where: { $0 === back }) {
                try panel.remove(at: index)
            }
            self.showsBack = showsBack
            panel.invalidateLayout()
        }
        if showsTitle != self.showsTitle {
            if showsTitle {
                try panel.insert(title, at: self.showsBack ? 1 : 0)
            } else if let index = panel.children.firstIndex(where: { $0 === title }) {
                try panel.remove(at: index)
            }
            self.showsTitle = showsTitle
            panel.invalidateLayout()
        }
    }

    /// The header row's height: its tallest part and the insets, 0 without a header.
    private var headerHeight: Double {
        guard showsBack || showsTitle else { return 0 }
        return max(showsBack ? measuredBack.height : 0, showsTitle ? measuredTitle.height : 0) + 2 * Self.headerInset
    }

    private var titleX: Double {
        showsBack ? Self.headerInset + measuredBack.width + Self.titleGap : Self.titleInset
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let unbounded = ActionUIWinUISize(width: .infinity, height: .infinity)
        measuredBack = showsBack ? back.measure(unbounded) : ActionUIWinUISize(width: 0, height: 0)
        measuredTitle = showsTitle ? title.measure(unbounded) : ActionUIWinUISize(width: 0, height: 0)
        let header = headerHeight
        // The title does not widen the stack (it is cut at the trailing edge), as SwiftUI's navigation
        // title does not; the back button does.
        let headerWidth = showsBack ? measuredBack.width + 2 * Self.headerInset : 0
        let room = ActionUIWinUISize(width: available.width,
                                     height: available.height.isFinite ? max(available.height - header, 0) : .infinity)
        measuredPage = page.panel.object.measureRequested(room)
        return ActionUIWinUISize(width: max(headerWidth, measuredPage.width), height: header + measuredPage.height)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let header = headerHeight
        if showsBack {
            back.arrange(ActionUIWinUIRect(x: Self.headerInset, y: ((header - measuredBack.height) / 2).rounded(.down),
                                           width: measuredBack.width, height: measuredBack.height))
        }
        if showsTitle {
            // Cut at the stack's trailing edge when it is narrower than the title.
            let x = titleX
            title.arrange(ActionUIWinUIRect(x: x, y: ((header - measuredTitle.height) / 2).rounded(.down),
                                            width: max(min(measuredTitle.width, finalSize.width - x - Self.headerInset), 0),
                                            height: measuredTitle.height))
        }
        let pageSize = ActionUIWinUISize(width: finalSize.width, height: max(finalSize.height - header, 0))
        page.panel.object.arrange(ActionUIWinUIRect(x: 0, y: header, width: pageSize.width, height: pageSize.height))
        if pageSize.width != clippedPage.width || pageSize.height != clippedPage.height {
            if actionUIWinUIElementSetClipSize(page.panel.object.pointer, pageSize.width, pageSize.height) {
                clippedPage = pageSize
            } else {
                ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("clipping the page"))", .error)
            }
        }
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

    init(layout: NavigationStackLayout) {
        self.layout = layout
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

        // The top screen's title; the root's falls back to the stack's own. An empty title is none.
        var title = top.flatMap { ScreenTitle.find(in: $0.element, windowModel: node.windowModel) }
        if title == nil, state.entries.isEmpty, let own = BaseModifiers(node.properties).navigationTitle, !own.isEmpty {
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
            try layout.setHeader(back: !state.entries.isEmpty, title: title != nil)
        } catch {
            ActionUIModel.shared.logger.log("NavigationStack: \(error)", .error)
        }
        // RenderNode enables the view, which is the layout's panel (no Control): the button is enabled here.
        if !actionUIWinUIElementSetEnabled(layout.back.pointer, !(node.isDisabled || node.isHidden)) {
            ActionUIModel.shared.logger.log("NavigationStack: \(WinUIError.last("enabling the back button"))", .error)
        }
        node.applyAccessibilityHidden(to: layout.back)
        node.applyAccessibilityHidden(to: layout.title)

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
