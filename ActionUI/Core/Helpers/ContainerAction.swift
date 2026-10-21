// Core/Helpers/ContainerAction.swift
//
// Whole-container tap dispatch: what makes a rich cell tappable as ONE target.
//
// A VStack / HStack / ZStack carrying an `actionID` fires it when tapped, so a
// data-driven cell (an avatar, a name, a status line) can be one tap target and one
// accessibility element instead of hanging a small glyph Button inside itself. Only the
// three stack containers apply this - making every element that happens to carry an
// `actionID` tappable would be a far larger change to hit-testing than the gap asks for
// and View.swift's modifier chain deliberately stays out of actionID for exactly
// that reason (see its note: "Do not handle actionID here").
//
// The dispatch convention mirrors Views/Button+SwiftUI.swift exactly, because a cell and a
// button inside that cell must address the same row the same way:
//   - inside a template row, the owning container's id is the viewID and the row index
//     is the viewPartID, both read from the throw-away instance's TemplateContext;
//   - outside one, the element's own id with viewPartID 0.
//
// The template case is the whole point: TemplateHelper builds throw-away instances, so a
// cloned cell's own id identifies nothing.
//
// (The tap itself, for SwiftUI, is in Helpers/ContainerAction+SwiftUI.swift.)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum ContainerAction {

    /// The element types a container tap applies to. Only these three - making every element
    /// carrying an `actionID` tappable would change hit-testing far more broadly than the gap
    /// asks for. Kept here so the registry and the tests agree on one list.
    static let tappableTypes: Set<String> = ["VStack", "HStack", "ZStack"]

    /// The resolved dispatch for a tappable container, or nil when it declares no action.
    struct Dispatch: Equatable {
        let actionID: String
        let viewID: Int
        let viewPartID: Int
    }

    /// Pure resolution of the container's tap dispatch - separated from the modifier so
    /// the identity rule is unit-testable without building a SwiftUI hierarchy.
    ///
    /// Returns nil when:
    ///  - the element is not one of `tappableTypes`;
    ///  - there is no `actionID`, or it is present but blank (a blank action would wire a tap
    ///    target dispatching an unroutable empty id, which reads to a user as a dead cell
    ///    rather than as an authoring mistake);
    ///  - the element itself resolves `disabled: true`. That has to be checked HERE rather
    ///    than left to SwiftUI: `View.applyModifiers` applies `.disabled()` to the container's
    ///    own subtree, and the tap is attached OUTSIDE that, so the environment would not
    ///    suppress it. An ancestor's disablement is a different matter and does reach the tap
    ///    through the environment - see `ContainerActionView`.
    static func resolve(
        element: any ActionUIElementBase,
        properties: [String: Any],
        templateContext: TemplateContext?
    ) -> Dispatch? {
        guard tappableTypes.contains(element.type) else { return nil }
        guard properties["disabled"] as? Bool != true else { return nil }
        guard let actionID = properties["actionID"] as? String,
              !PlainText.trimmed(actionID).isEmpty else { return nil }
        return Dispatch(
            actionID: actionID,
            viewID: templateContext?.parentID ?? element.id,
            viewPartID: templateContext?.rowIndex ?? 0
        )
    }
}
