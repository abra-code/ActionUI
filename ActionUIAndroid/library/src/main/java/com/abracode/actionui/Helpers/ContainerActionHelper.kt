package com.abracode.actionui.Helpers

import androidx.compose.foundation.clickable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel

/**
 * Whole-container tap dispatch: what makes a rich cell tappable as ONE target.
 *
 * A `VStack` / `HStack` / `ZStack` carrying an `actionID` fires it when tapped, so a
 * data-driven cell (an avatar, a name, a status line) can be one tap target and one
 * accessibility action instead of hanging a small glyph `Button` inside itself. Only
 * the three stack containers call this - a tap on every element that happens to carry
 * an `actionID` would be a much larger change to hit-testing than the gap asks for.
 *
 * Mirrors `Views/Button.kt`'s dispatch convention exactly, because a cell and a button
 * inside that cell must address the same row the same way:
 *  - inside a template row, the owning `List`/`Section` id is the `viewID` and the row
 *    index is the `viewPartID`, both read from [LocalTemplateContext];
 *  - outside one, the element's own id with `viewPartID` 0.
 *
 * The template case is the whole point: `Helpers/TemplateHelper.kt` builds throw-away
 * instances, so a cloned cell's own id identifies nothing.
 */

/** The resolved dispatch for a tappable container, or null when it declares no action. */
internal data class ContainerActionDispatch(
    val actionID: String,
    val viewID: Int,
    val viewPartID: Int,
)

/**
 * The element types a container tap applies to. Mirrors Apple's `ContainerAction.tappableTypes`.
 * Only the three stacks call [containerActionModifier], so this is belt and braces - but it puts
 * the list somewhere a unit test can reach, which is the only way ZStack gets any coverage at
 * all given the wiring itself is `@Composable`.
 */
internal val TAPPABLE_CONTAINER_TYPES = setOf("VStack", "HStack", "ZStack")

/**
 * Pure resolution of [element]'s container tap dispatch under [templateContext] -
 * separated from the modifier so the identity rule is unit-testable without composing
 * (`@Composable` code is deliberately not unit-tested in this library).
 *
 * Returns null when the element is not a tappable container type, or when there is no
 * `actionID`, or when it is present but blank: a blank action would wire a tap target that
 * dispatches an unroutable empty id, which reads to a user as a dead cell rather than as an
 * authoring mistake.
 *
 * `disabled` is deliberately NOT checked here. On Android it is carried by
 * [LocalActionUIEnabled], which already folds in both this element's own `disabled` and any
 * ancestor's, and which is only readable in composition - so it gates the `clickable` in
 * [containerActionModifier] instead. Apple has to check the element's own `disabled` in its
 * resolver because its tap attaches outside the `.disabled()` scope; the hosts arrive at the
 * same behavior by different routes.
 */
internal fun containerActionDispatch(
    element: ActionUIElement,
    templateContext: TemplateContext?,
): ContainerActionDispatch? {
    if (element.type !in TAPPABLE_CONTAINER_TYPES) return null
    val actionID = element.properties?.stringProperty("actionID")?.takeIf { it.isNotBlank() }
        ?: return null
    return ContainerActionDispatch(
        actionID = actionID,
        viewID = templateContext?.parentID ?: element.id,
        viewPartID = templateContext?.rowIndex ?: 0,
    )
}

/**
 * Wraps [modifier] in the container tap when [element] declares an `actionID`, and returns
 * it unchanged when it does not - so a container without one keeps exactly the modifier
 * chain it had and stays a pure layout node.
 *
 * **The clickable goes OUTERMOST, which is why this takes the chain rather than extending
 * it.** Compose applies modifiers left to right, outer to inner, so `modifier.clickable {}`
 * would put the tap INSIDE the padding and sizing that `applyInnerProperties` already added -
 * the canonical modifier-order trap - and a padded row would carry a dead ring exactly where
 * the author asked for breathing room. `clickable` first means the target is the container's
 * final laid-out box.
 *
 * Putting it outside does not weaken `hidden`: `hiddenSubtree()` consumes on
 * [androidx.compose.ui.input.pointer.PointerEventPass.Initial], which is dispatched outer to
 * inner, while `clickable` waits for an unconsumed down on the Main pass (inner to outer). A
 * hidden subtree therefore still swallows the press before this ever sees it.
 *
 * `enabled` is read from [LocalActionUIEnabled], as every other clickable in the library does
 * (`Views/Button.kt`, `Views/NavigationLink.kt`, `Views/DisclosureGroup.kt`). That local
 * already accounts for both the element's own `disabled` and an ancestor's, so a disabled
 * container is inert here exactly as it is on Apple and on the web - and gets no ripple.
 *
 * A `Button` (or any other `clickable`) nested inside consumes the press itself, so the cell
 * action does not also fire. Apple reaches the same outcome structurally; the web has to
 * check explicitly, because a DOM click bubbles (`Common/ModifierResolver.js`).
 */
@Composable
internal fun containerActionModifier(element: ActionUIElement, modifier: Modifier): Modifier {
    val dispatch = containerActionDispatch(element, LocalTemplateContext.current) ?: return modifier
    val enabled = LocalActionUIEnabled.current
    val onClick = remember(dispatch) {
        {
            ActionUIModel.actionHandler(
                dispatch.actionID,
                viewID = dispatch.viewID,
                viewPartID = dispatch.viewPartID,
            )
        }
    }
    return Modifier
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .then(modifier)
}
