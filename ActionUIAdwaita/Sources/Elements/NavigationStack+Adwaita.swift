// Sources/Elements/NavigationStack+Adwaita.swift
/*
 NavigationStack on GTK: an AdwNavigationView. The content is the root page; each pushed screen is
 a page of its own. Every page has its own header bar, the GNOME way, with the page's title (its
 element's navigationTitle; the root's falls back to the stack's own, then the window's) and a
 back button. A stack that is the window's whole document takes the window's place for a header
 bar (AdwaitaApplication shows none of its own), so its header bars carry the window's buttons.

 What is pushed, as on Apple (NavigationStack+SwiftUI.swift):
 - states["navigationPath"], [Int]: the destinations pushed, by id, from "destinations". Writing it
   pushes or pops; the user's back (the back button, Escape, a swipe) writes it.
 - A NavigationLink with destinationViewId pushes that destination; one with an inline
   "destination" pushes that view, which is not in the path, as SwiftUI's view-destination link is
   not (NavigationLink+Adwaita.swift).
 - The selectable-list pattern: when the content is a List with an actionID whose children have
   destinationViewId, choosing a child makes the path that destination (after the List's own
   selection and action), and backing out to the root clears the List's selection.

 The pages follow the path: a path that grows by one pushes (animated), one that shrinks pops back
 (animated), anything else replaces the stack. The toolbars of the views on a page show in its
 header bar (ScreenBar, NodeToolbar); the stack's persistentToolbar (and its toolbar, the deprecated
 alias) shows on every page, at the outer edge of the bar, after a split view's when the stack is its
 detail.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import Dispatch

/// One screen above the root: its element, and the destination id when it came from the path.
struct NavigationEntry {
    let element: any ActionUIElementBase
    let destinationID: Int?
    /// The title of the link that pushed it, for a screen with no navigationTitle.
    var linkTitle: String? = nil
}

/// What a NavigationStack's view shows: its root page and the pushed screens, kept on the view.
@MainActor
final class NavigationStackState {
    let view: OpaquePointer
    let rootPage: OwnedObject
    let rootToolbar: OpaquePointer
    /// The root page's header bar.
    let rootHeader: WidgetPointer
    /// The screens above the root, in order.
    var entries: [NavigationEntry] = []
    /// The page of each pushed screen, by its element's id, with its toolbar view and header bar.
    var pages: [Int: NavigationPage] = [:]
    /// The header bars, which show the window's buttons only on the window's own stack.
    var headerBars: [WidgetPointer] = []

    init(view: OpaquePointer, rootPage: consuming OwnedObject, rootToolbar: OpaquePointer, rootHeader: WidgetPointer) {
        self.view = view
        self.rootPage = rootPage
        self.rootToolbar = rootToolbar
        self.rootHeader = rootHeader
    }

    /// The destination ids of the entries: what the path should hold.
    var path: [Int] { entries.compactMap(\.destinationID) }
}

/// A pushed screen's page, its toolbar view (the content under a header bar) and the header bar.
@MainActor
final class NavigationPage {
    let page: OwnedObject
    let toolbar: OpaquePointer
    let header: WidgetPointer

    init(page: consuming OwnedObject, toolbar: OpaquePointer, header: WidgetPointer) {
        self.page = page
        self.toolbar = toolbar
        self.header = header
    }
}

let navigationStackStateKey = AttachKey<NavigationStackState>("actionui-navigation-stack")

extension NavigationStack: ActionUIAdwaitaRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let view = adw_navigation_view_new()!
        // Fills what it is offered, as SwiftUI's does: a root stack with small content still spans
        // the window, and a stack in a split view column the column.
        gtk_widget_set_hexpand(view, 1)
        gtk_widget_set_vexpand(view, 1)
        let (rootToolbar, rootHeader) = makePageToolbar()
        let rootPage = OwnedObject(retaining: UnsafeMutableRawPointer(adw_navigation_page_new(rootToolbar, "")!))
        let state = NavigationStackState(view: OpaquePointer(view), rootPage: rootPage, rootToolbar: OpaquePointer(rootToolbar), rootHeader: rootHeader)
        state.headerBars.append(rootHeader)
        adw_navigation_view_add(OpaquePointer(view), state.rootPage.typed())
        attach(state, to: view, key: navigationStackStateKey)
        // The user's back: the stack is shorter now; the path follows.
        connectUserSignal(view, "popped", .instanceAndArgument) { [weak node] in
            guard let node else { return }
            userPopped(node)
        }
        // The root page's title may fall back to the window's, known once the stack is in a window.
        connectSignal(view, "map", .instanceOnly) { [weak node] in
            guard let node else { return }
            SyncScheduler.shared.markDirty(node)
        }
        return view
    }

    /// A page's toolbar view, a header bar on top (shows the page's title and the back button).
    private static func makePageToolbar() -> (toolbar: WidgetPointer, header: WidgetPointer) {
        let toolbar = adw_toolbar_view_new()!
        let header = adw_header_bar_new()!
        adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
        return (toolbar, header)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: navigationStackStateKey) else { return }
        let element = node.effectiveElement
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []

        // A path the host wrote (or a destination link pushed) rebuilds the entries from it; one that
        // already matches keeps the inline screens among them.
        let path = node.model.states["navigationPath"] as? [Int] ?? []
        if path != state.path {
            // Back at the root of a selectable list by the host's path: as by the user's back. The
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

        var children: [any ActionUIElementBase] = content.map { [$0] } ?? []
        children += state.entries.map(\.element)
        // The items every screen shows: a split view's when the stack is its detail, then the stack's
        // own persistent toolbar (the outer container's first, as on Apple and Android).
        let persistent = NavigationSplitView.detailPersistentItems(node) + ToolbarHelper.persistentToolbarItems(of: element)
        node.syncChildren(children, insert: { child, index in
            if child.persistentToolbar == nil {
                child.persistentToolbar = NodeToolbar.persistent(on: child, items: persistent)
            }
            if child.element.id == content?.id {
                // The toolbars of the views on a page show in its header bar.
                if child.screenBar == nil {
                    child.screenBar = ScreenBar(header: state.rootHeader, toolbarView: WidgetPointer(state.rootToolbar))
                }
                if adw_toolbar_view_get_content(state.rootToolbar) != child.outerWidget {
                    adw_toolbar_view_set_content(state.rootToolbar, child.outerWidget)
                }
            } else if state.pages[child.element.id] == nil {
                let (toolbar, header) = makePageToolbar()
                adw_toolbar_view_set_content(OpaquePointer(toolbar), child.outerWidget)
                let page = OwnedObject(retaining: UnsafeMutableRawPointer(adw_navigation_page_new(toolbar, "")!))
                state.pages[child.element.id] = NavigationPage(page: page, toolbar: OpaquePointer(toolbar), header: header)
                child.screenBar = ScreenBar(header: header, toolbarView: toolbar)
                state.headerBars.append(header)
            }
        }, remove: { child in
            if child.element.id == content?.id {
                adw_toolbar_view_set_content(state.rootToolbar, nil)
            } else if let removed = state.pages.removeValue(forKey: child.element.id) {
                // The screen stays in its page, which libadwaita may still be sliding out; the page
                // and the screen's widgets go when libadwaita lets the page go.
                state.headerBars.removeAll { $0 == removed.header }
            }
        })

        // Titles, never empty (libadwaita needs one for the back button and assistive technologies):
        // each screen's navigationTitle, else the title of the link that pushed it, else the root's;
        // the root's falls back to the stack's, the window's, then the application's name.
        // An empty title counts as none.
        let stackTitle = nonEmpty(BaseModifiers(node.properties).navigationTitle)
        let rootTitle = content.flatMap { node.childNodes[$0.id] }.flatMap { nonEmpty(BaseModifiers($0.properties).navigationTitle) }
            ?? stackTitle ?? windowTitle(widget) ?? nonEmpty(AdwaitaApplication.shared.name) ?? ProcessInfo.processInfo.processName
        setTitle(state.rootPage.typed(), rootTitle)
        for entry in state.entries {
            guard let page = state.pages[entry.element.id], let child = node.childNodes[entry.element.id] else { continue }
            setTitle(page.page.typed(), nonEmpty(BaseModifiers(child.properties).navigationTitle) ?? nonEmpty(entry.linkTitle) ?? rootTitle)
        }
        // The window's buttons on the stack's header bars only when the stack is the window's document.
        for header in state.headerBars where adw_header_bar_get_show_end_title_buttons(OpaquePointer(header)) != (node.isWindowRoot ? 1 : 0) {
            adw_header_bar_set_show_end_title_buttons(OpaquePointer(header), node.isWindowRoot ? 1 : 0)
            adw_header_bar_set_show_start_title_buttons(OpaquePointer(header), node.isWindowRoot ? 1 : 0)
        }

        showPages(state)
    }

    private static func setTitle(_ page: UnsafeMutablePointer<AdwNavigationPage>, _ title: String) {
        if swiftString(adw_navigation_page_get_title(page)) != title {
            adw_navigation_page_set_title(page, title)
        }
    }

    private static func nonEmpty(_ title: String?) -> String? {
        title?.isEmpty == false ? title : nil
    }

    /// The title of the window the stack is in, when it has one.
    private static func windowTitle(_ widget: WidgetPointer) -> String? {
        guard let root = gtk_widget_get_root(widget),
              Gtk.Widget(UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWidget.self)).isA(gtk_window_get_type()) else { return nil }
        let title = swiftString(gtk_window_get_title(UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)))
        return title?.isEmpty == false ? title : nil
    }

    /// Makes the view's stack the root page and the entries' pages: a push or a pop when the stack
    /// grows or shrinks by its end (animated), else a replacement.
    private static func showPages(_ state: NavigationStackState) {
        let wanted: [UnsafeMutablePointer<AdwNavigationPage>] = [state.rootPage.typed()]
            + state.entries.compactMap { state.pages[$0.element.id]?.page.typed() }
        let current = currentPages(state.view)
        guard current != wanted else { return }
        if current.count + 1 == wanted.count, Array(wanted.prefix(current.count)) == current, let last = wanted.last {
            adw_navigation_view_push(state.view, last)
        } else if wanted.count < current.count, Array(current.prefix(wanted.count)) == wanted, let last = wanted.last {
            adw_navigation_view_pop_to_page(state.view, last)
        } else {
            var pages: [UnsafeMutablePointer<AdwNavigationPage>?] = wanted
            adw_navigation_view_replace(state.view, &pages, Int32(pages.count))
        }
    }

    /// The pages in the view's navigation stack, root first.
    static func currentPages(_ view: OpaquePointer) -> [UnsafeMutablePointer<AdwNavigationPage>] {
        guard let stack = adw_navigation_view_get_navigation_stack(view) else { return [] }
        defer { g_object_unref(UnsafeMutableRawPointer(stack)) }
        return (0..<g_list_model_get_n_items(stack)).compactMap { index in
            guard let item = g_list_model_get_item(stack, index) else { return nil }
            g_object_unref(item)
            return item.assumingMemoryBound(to: AdwNavigationPage.self)
        }
    }

    // MARK: Navigating

    /// The user went back: the entries end where the view's stack ends now, and the path follows.
    private static func userPopped(_ node: RenderNode) {
        guard let state = attached(on: node.widget, key: navigationStackStateKey) else { return }
        let depth = max(0, currentPages(state.view).count - 1)
        guard depth < state.entries.count else { return }
        state.entries = Array(state.entries.prefix(depth))
        if (node.model.states["navigationPath"] as? [Int] ?? []) != state.path {
            node.model.states["navigationPath"] = state.path
        }
        // Back at the root of a selectable list: its selection clears, so the same row can be chosen again.
        if depth == 0, let list = selectableList(node) {
            list.model.value = [] as [String]
        }
        SyncScheduler.shared.markDirty(node)
    }

    /// Pushes `element` (a NavigationLink's inline destination, not in the path) on the stack
    /// `node` is in, or the destination `destinationID` from its "destinations".
    static func push(from node: RenderNode, element: (any ActionUIElementBase)?, destinationID: Int?) {
        guard let stack = enclosingStack(node), let state = attached(on: stack.widget, key: navigationStackStateKey) else {
            ActionUIModel.shared.logger.log("NavigationLink \(node.element.id) is not in a NavigationStack", .warning)
            return
        }
        let entry: NavigationEntry
        if let element {
            entry = NavigationEntry(element: element, destinationID: nil, linkTitle: linkTitle(node))
        } else if let destinationID {
            let destinations = stack.effectiveElement.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
            guard let destination = destinations.first(where: { $0.id == destinationID }) else {
                ActionUIModel.shared.logger.log("NavigationStack \(stack.element.id): no destination \(destinationID)", .warning)
                return
            }
            entry = NavigationEntry(element: destination, destinationID: destinationID, linkTitle: linkTitle(node))
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
              content.type == "List", let list = stack.childNodes[content.id],
              List.Props(list.properties).actionID != nil,
              !(stack.effectiveElement.subviews?["destinations"] as? [any ActionUIElementBase] ?? []).isEmpty else { return nil }
        return list
    }

    /// The title of `node` when it is a NavigationLink.
    private static func linkTitle(_ node: RenderNode) -> String? {
        node.element.type == "NavigationLink" ? NavigationLink.Props(node.properties).title : nil
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
