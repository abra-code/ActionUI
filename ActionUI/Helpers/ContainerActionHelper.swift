// Helpers/ContainerActionHelper.swift
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
// The dispatch convention mirrors Views/Button.swift exactly, because a cell and a
// button inside that cell must address the same row the same way:
//   - inside a template row, the owning container's id is the viewID and the row index
//     is the viewPartID, both read from the throw-away instance's TemplateContext;
//   - outside one, the element's own id with viewPartID 0.
//
// The template case is the whole point: TemplateHelper builds throw-away instances, so a
// cloned cell's own id identifies nothing.

import SwiftUI

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
              !actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Dispatch(
            actionID: actionID,
            viewID: templateContext?.parentID ?? element.id,
            viewPartID: templateContext?.rowIndex ?? 0
        )
    }

    /// Wraps `view` in the container tap when `element` is a tappable container declaring an
    /// `actionID`, and returns it UNTOUCHED otherwise - not even an `AnyView` wrap - so a
    /// container without one keeps exactly the view tree it had and stays a pure layout node.
    /// That matters beyond tidiness: an unconditional `.contentShape` would turn every stack
    /// into a hit target, and a ZStack sibling would start swallowing taps meant for the view
    /// behind it.
    ///
    /// **Call it AFTER the base view modifiers, not inside `buildView`.** The tap must cover
    /// the container's FINAL box - its `frame`, `padding` and `background` - which
    /// `View.applyModifiers` adds after the element builds. Applied inside `buildView` the
    /// shape sizes to the stack's intrinsic content instead, so a padded, full-width, tinted
    /// row would be tappable only where its children happen to draw and dead everywhere else.
    /// `ActionUIRegistry.applyViewModifiers` is the one place that ordering is guaranteed.
    ///
    /// `.contentShape(SwiftUI.Rectangle())` is what makes the whole box tappable rather than
    /// only the drawn pixels. It must be spelled `SwiftUI.Rectangle` - ActionUI ships its own
    /// `Rectangle` element (Views/Rectangle.swift), which shadows SwiftUI's inside this module
    /// and does not conform to `Shape`.
    ///
    /// A Button (or any other control) nested inside keeps its own tap: SwiftUI resolves a tap
    /// to the innermost control, so the cell action does not also fire. Measured, not assumed -
    /// see ActionUITestAppUITests/ContainerActionTests.swift, where swapping this for
    /// `.simultaneousGesture` fails exactly that assertion.
    ///
    /// `@MainActor` because it reads the ViewModel and dispatches through ActionUIModel, both
    /// main-actor isolated.
    @MainActor
    static func apply(
        _ view: any SwiftUI.View,
        element: any ActionUIElementBase,
        model: ViewModel,
        windowUUID: String,
        properties: [String: Any]
    ) -> any SwiftUI.View {
        guard let dispatch = resolve(
            element: element,
            properties: properties,
            templateContext: model.templateContext
        ) else { return view }
        return ContainerActionView(content: AnyView(view), dispatch: dispatch, windowUUID: windowUUID)
    }
}

/// The tap itself, as a View rather than a bare modifier chain, so it can read
/// `\.isEnabled`.
///
/// An ANCESTOR's `disabled: true` reaches here through the environment - this view is inside
/// that ancestor's subtree - and must suppress the dispatch, the same way it suppresses a
/// Button. The container's OWN `disabled` does not: `View.applyModifiers` applies `.disabled()`
/// to the container's subtree, and this wrapper sits outside it, so that case is caught in
/// `ContainerAction.resolve` instead. Between the two, both directions are covered.
@MainActor
private struct ContainerActionView: SwiftUI.View {
    @Environment(\.isEnabled) private var isEnabled

    let content: AnyView
    let dispatch: ContainerAction.Dispatch
    let windowUUID: String

    var body: some SwiftUI.View {
        content
            .contentShape(SwiftUI.Rectangle())
            .onTapGesture {
                guard isEnabled else { return }
                ActionUIModel.shared.actionHandler(
                    dispatch.actionID,
                    windowUUID: windowUUID,
                    viewID: dispatch.viewID,
                    viewPartID: dispatch.viewPartID
                )
            }
            // The accessibility half of "one tap target". Without it, VoiceOver sees the cell
            // as loose Texts and Images with no announced action, so the pattern would be an
            // improvement for a pointer and a regression for a screen reader - the opposite of
            // the reason to prefer it over a leading-glyph Button. Android's
            // `clickable(role = Role.Button)` merges descendants and sets the role for free;
            // this is Apple's equivalent.
            //
            // The trait ALONE, deliberately: `.accessibilityElement(children: .combine)` was
            // here and had to come out, because it is not symmetric across Apple platforms.
            // Measured by dumping the XCUITest hierarchy on both (iPhone SE 18.4 and macOS):
            //
            //   macOS  it really merges - every descendant leaves the tree, INCLUDING a nested
            //          Button, which a VoiceOver user then cannot reach at all. That trades a
            //          small-target cost for an unreachable control, which is strictly worse.
            //   iOS    it does not merge - the children stay exposed and the combined element
            //          is simply added alongside them, i.e. a duplicate rather than a merge.
            //
            // So it bought nothing on iOS and broke nested controls on macOS. The trait on its
            // own gives macOS the single announced button anyway (it absorbs the child Text as
            // the button's label) while leaving a nested Button reachable.
            .accessibilityAddTraits(.isButton)
    }
}
