// Core/Helpers/ToolbarHelper.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// The toolbar rules every renderer shares: which element types are navigation containers, and
// which toolbar items belong to a container or to a screen. Each renderer maps a placement name
// to its own placement type (SwiftUI: Helpers/ToolbarHelper+SwiftUI.swift).
enum ToolbarHelper {
    /// The placement name of a toolbar item: from its view model's current properties when they carry
    /// a placement, else from the element's own. ToolbarItem and ToolbarItemGroup parse it the same
    /// way: a name that is not one of theirs, or no string, is "automatic".
    static func placementName(current: [String: Any]?, element: [String: Any]) -> String {
        let source = current.flatMap { $0["placement"] != nil ? $0 : nil } ?? element
        return ToolbarItem.Props(source).placement.rawValue
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
