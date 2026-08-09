// Helpers/ToolbarHelper.swift

import SwiftUI

// Maps a JSON placement string to the SwiftUI ToolbarItemPlacement value.
// Platform-unavailable placements (e.g., "bottomBar" on macOS) fall back to .automatic.
enum ToolbarHelper {
    static func resolvePlacement(_ string: String?) -> ToolbarItemPlacement {
        switch string {
        case "automatic":
            return .automatic
        case "principal":
            return .principal
        case "confirmationAction":
            return .confirmationAction
        case "cancellationAction":
            return .cancellationAction
        case "destructiveAction":
            return .destructiveAction
        case "primaryAction":
            return .primaryAction
        case "secondaryAction":
            return .secondaryAction
        case "topBarLeading":
#if os(iOS) || os(visionOS)
            return .topBarLeading
#else
            return .automatic
#endif
        case "topBarTrailing":
#if os(iOS) || os(visionOS)
            return .topBarTrailing
#else
            return .automatic
#endif
        case "bottomBar":
#if os(iOS) || os(visionOS)
            return .bottomBar
#else
            return .automatic
#endif
        case "keyboard":
#if os(iOS) || os(visionOS)
            return .keyboard
#else
            return .automatic
#endif
        case "navigation":
#if os(macOS)
            return .navigation
#else
            return .automatic
#endif
        case "status":
#if os(macOS)
            return .status
#else
            return .automatic
#endif
        default:
            return .automatic
        }
    }

    // Element types that own a navigation context rather than being a single screen.
    // A toolbar authored on one of these belongs to the CONTAINER, not to the screen it
    // happens to be declared next to. Mirrors NAV_CONTAINER_TYPES in the web renderer.
    static let navigationContainerTypes: Set<String> = ["NavigationStack", "NavigationSplitView"]

    static func isNavigationContainer(_ elementType: String) -> Bool {
        navigationContainerTypes.contains(elementType)
    }

    // The items a navigation container must keep in the bar on every screen inside it:
    // its "persistentToolbar" array, plus its "toolbar" array as a DEPRECATED ALIAS.
    //
    // The alias exists because a container-level "toolbar" was never a screen toolbar on any
    // host: macOS applied it outside the stack (where it reached the shared window toolbar and
    // persisted), while iOS, Android and Web each dropped or misplaced it. Reading it here
    // gives all four hosts one behavior and keeps existing macOS documents working unchanged.
    // WindowModel logs a one-time deprecation warning naming the element when it sees one.
    //
    // Order is only meaningful against the SCREEN's own items, which are applied first so the
    // persistent ones sit at the outer edge; between these two keys it is unspecified, and a
    // document should author one or the other, never both.
    static func persistentToolbarItems(of element: any ActionUIElementBase) -> [any ActionUIElementBase] {
        guard let subviews = element.subviews else { return [] }
        let persistent = subviews["persistentToolbar"] as? [any ActionUIElementBase] ?? []
        let aliased = subviews["toolbar"] as? [any ActionUIElementBase] ?? []
        return persistent + aliased
    }

    // The items to apply as THIS SCREEN's toolbar, from the generic modifier pass in View.swift.
    //
    // Empty for a navigation container: its "toolbar" belongs to the container, not to a screen,
    // and its own builder applies it where this platform needs it. Applying it here as well would
    // put it in the macOS window toolbar twice. Kept as a function rather than an inline check so
    // the rule is unit-testable on every platform - the UI test that would otherwise catch a
    // regression here can only run on macOS.
    static func screenToolbarItems(of element: any ActionUIElementBase) -> [any ActionUIElementBase] {
        guard !isNavigationContainer(element.type) else { return [] }
        return element.subviews?["toolbar"] as? [any ActionUIElementBase] ?? []
    }
}

// Applies a navigation container's persistent items, at the one site that is correct for this
// platform. The two sites are ALTERNATIVES, never layers:
//
//   macOS  applies them ONCE outside the container. They land in the window toolbar, which the
//          whole stack shares, so they survive every push for free - including a push onto a
//          destination that declares no toolbar of its own (measured, PersistentToolbarTests).
//   iOS    has no window toolbar to escape to, and each pushed destination owns its bar, so the
//          container PUBLISHES its items to its subtree and each screen inside applies them to
//          its own bar. Multiple .toolbar modifiers accumulate (also measured), so this composes
//          with whatever the screen declares.
//
// Doing both on macOS would render every item TWICE, because the outer application and the top
// screen's items land in the same bar and accumulate. Hence: each entry point is a no-op on the
// platform where the other one is the right answer.
//
// KNOWN LIMITATION on the non-macOS side. A persistent item is now MOUNTED on several screens at
// once (the stack's root stays alive under a pushed destination), and every copy resolves to the
// one ViewModel behind its authored id. That is what makes setElementProperty work on all of them
// at once, and it is why this is safe for the state a host writes. It is NOT safe for state the
// ITEM owns: a Button that declares a `popover` or `sheet` subview binds presentation to
// states["popoverVisible"] on that single shared model, so every mounted copy would try to
// present at once. Keep persistent items to things that do not present - an indicator, or a
// button whose action the host handles - until presentation state is per-instance.
//
// Why the non-macOS half goes through the ENVIRONMENT rather than passing the array down by hand.
// A `.toolbar` applied to a view that CONTAINS a SwiftUI.NavigationStack does not reach the bars
// of the screens inside it - that is the whole reason iOS needed a merge in the first place. So a
// container cannot serve a nested container's screens by wrapping it; it can only announce its
// items and let the inner container merge them. That happens whenever a NavigationStack sits in a
// NavigationSplitView's detail column, which is the shape of this project's own split fixture and
// of SharedCare's wide shell.
@MainActor
enum PersistentToolbar {
    /// Wrap a navigation container. macOS applies the items outside it; elsewhere they are
    /// published to the subtree, where each screen inside picks them up.
    @ViewBuilder
    static func onContainer<Content: SwiftUI.View>(
        _ content: Content,
        items: [any ActionUIElementBase],
        windowUUID: String
    ) -> some SwiftUI.View {
        if items.isEmpty {
            // Nothing to publish or apply: a document without the key pays two dictionary
            // lookups and no extra view, and any items inherited from an OUTER container keep
            // flowing down untouched.
            content
        } else {
#if os(macOS)
            ToolbarModifierView(content: content, toolbarItems: items, windowUUID: windowUUID)
#else
            PersistentToolbarScope(content: content, items: items)
#endif
        }
    }

    /// Wrap ONE screen inside a navigation container - the stack's root, or a destination.
    /// No-op on macOS, where the window toolbar already carries the items for every screen.
    ///
    /// `element` is the screen's own element, when there is one. A screen that is ITSELF a
    /// navigation container is skipped for the same reason a split-view column is: the items
    /// would be applied around the inner container, landing in the OUTER bar, while the inner
    /// container's own screens apply them again from the environment - one item, two bars.
    /// Pass nil for a screen with no element behind it (the destination error views).
    ///
    /// The check is one level deep, matching the split-view path. A screen that merely CONTAINS
    /// a navigation container further down (a VStack wrapping a NavigationStack) still gets the
    /// items here and again inside, and no cheap check can see that from here - authoring a
    /// navigation container below the top of a screen is out of scope for this feature.
    @ViewBuilder
    static func onScreen<Content: SwiftUI.View>(
        _ content: Content,
        element: (any ActionUIElementBase)?,
        windowUUID: String
    ) -> some SwiftUI.View {
#if os(macOS)
        content
#else
        if let element, ToolbarHelper.isNavigationContainer(element.type) {
            content
        } else {
            PersistentToolbarScreen(content: content, windowUUID: windowUUID)
        }
#endif
    }

    /// Stop a container's published items at a presentation boundary.
    ///
    /// A sheet, popover or full-screen cover is built inside the presenting view's subtree, so it
    /// inherits that subtree's environment - including anything an enclosing NavigationStack
    /// published. Sheets very commonly host their own NavigationStack (for a Done button), and
    /// that stack's screens would then apply the PRESENTER's persistent items into the sheet's
    /// bar. A modal is its own presentation context with its own bar; the container behind it
    /// does not own that bar.
    @ViewBuilder
    static func acrossPresentation<Content: SwiftUI.View>(_ content: Content) -> some SwiftUI.View {
#if os(macOS)
        content
#else
        content.environment(\.inheritedPersistentToolbar, [])
#endif
    }

    /// Wrap one column of a NavigationSplitView, on the platforms whose columns each own a bar.
    ///
    /// Skipped entirely when the column is itself a navigation container: a toolbar applied
    /// around a NavigationStack does not reach the screens inside it, so that column's own
    /// builder merges the published items into each of ITS screens instead.
    ///
    /// The detail column otherwise always carries them - it is the column the user navigates,
    /// and in compact width it is what a push lands on. The leading columns (sidebar, and the
    /// middle column of a 3-pane) carry them only in COMPACT width, where SwiftUI collapses the
    /// split view into one stack rooted at the sidebar and they become screens of that stack. In
    /// regular width every visible column keeps its own bar side by side, so applying there too
    /// would show one indicator two or three times at once.
    ///
    /// No-op on macOS, where all columns share one window toolbar and onContainer covers them.
    @ViewBuilder
    static func onSplitViewColumn<Content: SwiftUI.View>(
        _ content: Content,
        windowUUID: String,
        isDetail: Bool,
        columnIsNavigationContainer: Bool
    ) -> some SwiftUI.View {
#if os(macOS)
        content
#else
        if isDetail {
            if columnIsNavigationContainer {
                // The column's own screens will apply the published items.
                content
            } else {
                PersistentToolbarScreen(content: content, windowUUID: windowUUID)
            }
        } else {
            LeadingColumn(content: content,
                          windowUUID: windowUUID,
                          columnIsNavigationContainer: columnIsNavigationContainer)
        }
#endif
    }
}

#if !os(macOS)
// The items published by the enclosing navigation container(s), innermost last.
private struct InheritedPersistentToolbarKey: EnvironmentKey {
    static let defaultValue: [any ActionUIElementBase] = []
}

// Whether the SCENE is compact, sampled outside any split view that declares persistent items.
//
// It has to be a separate key because `horizontalSizeClass` cannot be read from inside a column
// and mean what we need: UIKit overrides a split view child's traits, so a 320pt sidebar reports
// .compact even in a regular-width scene, and the leading-column rule below would then fire in
// exactly the case it exists to avoid.
//
// The qualifier is exact rather than pedantic. The first scope to write this wins, and a scope
// only exists where a container declares items - so a split view that declares NONE creates no
// scope, and a container inside one of ITS columns would be the first writer and would sample
// that column's overridden traits. Three levels of nesting, and the regular-width branch it
// feeds is unmeasured anyway, but the invariant is "outermost SCOPE", not "outermost container".
// nil means "nobody has sampled it yet", which is what makes the FIRST scope the only writer -
// see PersistentToolbarScope. Readers treat nil as not-compact.
private struct SceneIsCompactKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    fileprivate var inheritedPersistentToolbar: [any ActionUIElementBase] {
        get { self[InheritedPersistentToolbarKey.self] }
        set { self[InheritedPersistentToolbarKey.self] = newValue }
    }
    fileprivate var sceneIsCompact: Bool? {
        get { self[SceneIsCompactKey.self] }
        set { self[SceneIsCompactKey.self] = newValue }
    }
}

// Publishes a container's persistent items to its subtree, appended to anything an outer
// container already published, and records the scene's size class while we are still outside
// any split view.
@MainActor
private struct PersistentToolbarScope<Content: SwiftUI.View>: SwiftUI.View {
    @Environment(\.inheritedPersistentToolbar) private var inherited
    @Environment(\.sceneIsCompact) private var alreadySampled
    // Only the platforms that actually collapse a split view need the size class, and it is only
    // those that are guaranteed to vend it. Everywhere else the default (not compact) is right.
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
#else
    private var isCompact: Bool { false }
#endif
    let content: Content
    let items: [any ActionUIElementBase]

    var body: some SwiftUI.View {
        content
            .environment(\.inheritedPersistentToolbar, inherited + items)
            // Only the OUTERMOST scope samples the width. An inner container sits inside whatever
            // its ancestors built - quite possibly a split-view column, whose traits UIKit forces
            // to compact - so its reading would be the very lie this key exists to avoid.
            .environment(\.sceneIsCompact, alreadySampled ?? isCompact)
    }
}

// Applies whatever the enclosing containers published to one screen's own toolbar.
@MainActor
private struct PersistentToolbarScreen<Content: SwiftUI.View>: SwiftUI.View {
    @Environment(\.inheritedPersistentToolbar) private var items
    let content: Content
    let windowUUID: String

    var body: some SwiftUI.View {
        if items.isEmpty {
            content
        } else {
            ToolbarModifierView(content: content, toolbarItems: items, windowUUID: windowUUID)
        }
    }
}

// A LEADING split-view column (the sidebar, and the middle column of a 3-pane).
//
// In compact width the split view has collapsed into one stack rooted at the sidebar, so these
// columns are screens and carry the items - directly if the column is an ordinary view, or via its
// own screens if the column is itself a navigation container. In regular width they are columns
// beside the detail, each with its own bar, so the items are WITHDRAWN from the whole subtree:
// declining to apply them to the column itself is not enough, because a navigation container
// anywhere below would still find them published and apply them to its own screens. That is the
// one indicator appearing twice side by side that this rule exists to prevent.
//
// A note on identity, because an earlier version of this claimed something false. The branch below
// changes view identity when the width class flips, so the column's scroll position and focus do
// not survive a rotation. Passing an empty item array through ToolbarModifierView instead does NOT
// avoid that - its body is an AnyView, and the boxed type changes with the item count either way.
// Crossing that boundary already restructures a split view (the columns become stack screens), so
// this is not worth more machinery; it is recorded rather than fixed.
@MainActor
private struct LeadingColumn<Content: SwiftUI.View>: SwiftUI.View {
    @Environment(\.sceneIsCompact) private var sceneIsCompact
    @Environment(\.inheritedPersistentToolbar) private var items
    let content: Content
    let windowUUID: String
    let columnIsNavigationContainer: Bool

    var body: some SwiftUI.View {
        if sceneIsCompact == true {
            if columnIsNavigationContainer {
                content
            } else {
                ToolbarModifierView(content: content, toolbarItems: items, windowUUID: windowUUID)
            }
        } else {
            content.environment(\.inheritedPersistentToolbar, [])
        }
    }
}
#endif

// Applies toolbar items declared in a view's "toolbar" subview array.
// Each item gets its own .toolbar {} call - multiple .toolbar modifiers are additive in SwiftUI
// and accumulate their items in the containing NavigationStack or NavigationSplitView.
// Using one .toolbar per item avoids @ToolbarContentBuilder ForEach overload ambiguity with
// existential arrays. ToolbarItemGroup entries use SwiftUI.ToolbarItemGroup for system-managed
// multi-item grouping; ToolbarItem entries use SwiftUI.ToolbarItem. Mirrors SheetModifierView pattern.
//
// body returns AnyView so that the for-loop imperative logic is not inside @ViewBuilder.
@MainActor
struct ToolbarModifierView<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let toolbarItems: [any ActionUIElementBase]
    let windowUUID: String

    var body: AnyView {
        var view: AnyView = AnyView(content)
        for item in toolbarItems {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            // Prefer validated placement from the ViewModel; fall back to raw property.
            let placementStr = windowModel?.viewModels[item.id]?.validatedProperties["placement"] as? String
                ?? item.properties["placement"] as? String
            let placement = ToolbarHelper.resolvePlacement(placementStr)
            let capturedItem = item
            let capturedWindowUUID = windowUUID
            if item.type == "ToolbarItemGroup" {
                view = AnyView(
                    view.toolbar {
                        SwiftUI.ToolbarItemGroup(placement: placement) {
                            ToolbarItemGroupContentView(element: capturedItem, windowUUID: capturedWindowUUID)
                        }
                    }
                )
            } else {
                view = AnyView(
                    view.toolbar {
                        SwiftUI.ToolbarItem(placement: placement) {
                            ToolbarItemContentView(element: capturedItem, windowUUID: capturedWindowUUID)
                        }
                    }
                )
            }
        }
        return view
    }
}

// Renders the single "content" element declared inside a ToolbarItem.
// ToolbarItem occupies exactly one toolbar slot; composite layouts (HStack, ZStack, etc.)
// are the caller's responsibility, not the toolbar's.
@MainActor
private struct ToolbarItemContentView: SwiftUI.View {
    let element: any ActionUIElementBase
    let windowUUID: String

    var body: some SwiftUI.View {
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        if let content = element.subviews?["content"] as? (any ActionUIElementBase),
           let contentModel = windowModel?.viewModels[content.id] {
            ActionUIView(element: content, model: contentModel, windowUUID: windowUUID)
        }
    }
}

// Renders the "children" array declared inside a ToolbarItemGroup.
// Each child is an independent toolbar item managed by the system - spacing, overflow,
// and platform-specific grouping are handled by SwiftUI, not the content view.
@MainActor
private struct ToolbarItemGroupContentView: SwiftUI.View {
    let element: any ActionUIElementBase
    let windowUUID: String

    var body: some SwiftUI.View {
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        ForEach(children, id: \.id) { child in
            if let childModel = windowModel?.viewModels[child.id] {
                ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
            }
        }
    }
}
