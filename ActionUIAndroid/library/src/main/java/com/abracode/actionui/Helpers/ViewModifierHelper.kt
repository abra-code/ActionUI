package com.abracode.actionui.Helpers

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyInnerProperties
import com.abracode.actionui.Common.applyOuterProperties
import com.abracode.actionui.Common.parseAlignment
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * The shared build entry point: every container child loop (and every root-like context -
 * window root, navigation screen, modal, toolbar item) calls
 * [BuildViewWithModifiers] instead of `BuildView`. It resolves the element's
 * full modifier pipeline - the common properties (`ModifierResolver`) plus the
 * subview-carrying modifiers, the Android mirror of the view-based modifiers
 * in Apple's `View.swift`:
 *
 *   * `searchable` - the List / NavigationStack search field; wrapped outermost
 *     in a `Column` above the content ([BuildViewWithSearchable],
 *     `SearchableHelper.kt`).
 *   * `popover` - the anchored presentation; wrapped because a Compose `Popup`
 *     anchors to the layout node it is composed in (`PopoverHelper.kt`).
 *   * `overlay` / `background` - the decoration subviews, composed here in a
 *     `Box` around the element ([BuildViewWithDecorations]).
 *
 * Four runtime concerns also resolve here, before anything else, because
 * this is the one place every rendered element passes through:
 *
 *   * **Property overrides** - `ActionUIModel.setElementProperty` writes merge
 *     over the authored properties ([effectiveElement]), so host mutations
 *     reach the chain and the builder; Apple's equivalent is views reading the
 *     mutated `validatedProperties`.
 *   * **The `animation` modifier** - [rememberElementAnimator]
 *     (`AnimationHelper.kt`) turns the element's `animation` declaration into
 *     an [ElementAnimator] threaded through the chain halves, animating their
 *     visual values toward host-mutated targets.
 *   * **The lifecycle action hooks** - [ElementActionHooks]
 *     (`ActionHookHelper.kt`): `onAppearActionID` / `onDisappearActionID`
 *     fire on composition entry/exit (SwiftUI `.onAppear`/`.onDisappear`),
 *     `openURLActionID` registers for host-delivered URLs
 *     (`ActionUIModel.onOpenURL`, SwiftUI `.onOpenURL`).
 *   * **Scroll targets** - inside a `ScrollViewReader`, every element with a
 *     positive id registers its coordinates ([scrollTargetModifier],
 *     `ScrollReaderHelper.kt`) so the reader's `scrollTo` can address it.
 *
 * Callers pass only the scope-restricted parent data (`weight`/`align`, via
 * `buildChildModifier`) or `Modifier`; the element's own properties are
 * resolved HERE, not at the call site, because the decoration wrap must split
 * the chain around its `Box`: the outer half (`applyOuterProperties` -
 * transforms, offset, opacity) lands on the `Box` so decorations move and fade
 * with the carrier, the inner half (`applyInnerProperties` - frame, padding,
 * clip, background color) lands on the element inside so decorations cover
 * the frame-plus-padding box and are not clipped by the carrier's rounding.
 *
 * **Decoration semantics - Apple's `.overlay(alignment:)` / `.background(alignment:)`.**
 * A decoration never affects the carrier's layout size (`matchParentSize`);
 * it is positioned by the `overlayAlignment` / `backgroundAlignment` property
 * (default `center`) against the carrier's box and may overflow it
 * (`wrapContentSize(unbounded = true)` - a 56dp `Circle` behind a 44dp `Text`
 * sticks out on both sides, as SwiftUI's soft proposals allow). Draw order is
 * background, element, overlay - so a `background` sits behind the element's
 * own `background` color fill, exactly Apple's modifier order.
 *
 * Known divergences (documented, demo-invisible):
 *   * The carrier's `cornerRadius`/`clipShape` does not clip the `background`
 *     subview (on Apple it does; the `overlay` is unclipped on both, which is
 *     the visible case - corner badges). Background subviews are typically
 *     self-shaped (`Capsule`, `RoundedRectangle`), where this cannot show.
 *   * Decorations on a `Group` wrap the group as one unit; Apple applies
 *     view-based modifiers on a `Group` to each child separately. (The same
 *     pre-existing divergence as `popover` on a `Group`.)
 *
 * The per-row `template` path is excluded, as for the modals and `popover`:
 * `TemplateHelper` keeps calling `BuildView` directly with a fused chain, and
 * throw-away row instances carry no decoration subviews.
 */
@Composable
fun ActionUIViewConstruction.BuildViewWithModifiers(element: ActionUIElement, modifier: Modifier) {
    // Runtime property overrides (ActionUIModel.setElementProperty) merge into
    // the element here, so every consumer below - the modifier chain and the
    // element builder - sees host mutations; reading the override map
    // subscribes this composition to future writes. The element's `animation`
    // declaration (if any) is resolved against the same effective element, so
    // chain targets and the watched trigger move in one recomposition.
    val effective = effectiveElement(element)
    // The `transition` modifier (TransitionHelper.kt): a freshly-inserted element with a
    // `transition` plays its entrance once via AnimatedVisibility (gated by wasDynamicallyInserted
    // so initial-load views do not animate in). Removal/exit is instant - documented divergence
    // from Apple (the diff drops the node before an exit can play).
    //
    // The entrance plays AT MOST ONCE per element: AnimatedVisibility's remember/LaunchedEffect state
    // is keyed by composition position, so reordering the container (e.g. a later prepend that shifts
    // this row down a slot) would otherwise re-init that state and replay the entrance. The
    // WindowModel.transitionPlayed ledger (not composition-scoped) gates that off once the entrance
    // has run, so a row animates in only when it is first inserted.
    val windowModel = LocalWindowModel.current
    val enter = if (effective.id > 0 && effective.properties?.get("transition") != null &&
        windowModel?.wasDynamicallyInserted(effective.id) == true &&
        windowModel.hasPlayedTransition(effective.id) == false
    ) {
        resolveEnterTransition(effective.properties?.get("transition"))
    } else {
        null
    }
    if (enter != null) {
        val visibleState = remember(effective.id) { MutableTransitionState(false) }
        LaunchedEffect(effective.id) { visibleState.targetState = true }
        // Record the entrance as played once it settles, so it is not replayed on a later reorder.
        LaunchedEffect(visibleState.isIdle) {
            if (visibleState.isIdle && visibleState.currentState) {
                windowModel?.markTransitionPlayed(effective.id)
            }
        }
        AnimatedVisibility(visibleState = visibleState, enter = enter, exit = ExitTransition.None) {
            this@BuildViewWithModifiers.BuildViewModifierChain(effective, modifier)
        }
    } else {
        BuildViewModifierChain(effective, modifier)
    }
}

/**
 * The resolved modifier pipeline for [effective] (the host-merged element from
 * [effectiveElement]). Split from [BuildViewWithModifiers] so the `transition`
 * entrance can wrap it in an `AnimatedVisibility` without re-merging the element.
 */
@Composable
private fun ActionUIViewConstruction.BuildViewModifierChain(effective: ActionUIElement, modifier: Modifier) {
    // The lifecycle action hooks (onAppearActionID / onDisappearActionID /
    // openURLActionID - ActionHookHelper.kt) attach here so they cover both
    // the popover route and the plain one.
    ElementActionHooks(effective)
    // Inside a ScrollViewReader, an element with a positive id is a scroll
    // target: its coordinates register with the reader (ScrollReaderHelper.kt).
    // Identity modifier outside a reader.
    // ignoresSafeArea folds into the carrier: it consumes the chosen safe-drawing edges so a
    // descendant safeAreaInset no longer pads for them (Android is edge-to-edge by default).
    val targeted = scrollTargetModifier(effective, modifier).then(ignoresSafeAreaModifier(effective.properties))
    val animator = rememberElementAnimator(effective)
    val logger = LocalActionUILogger.current
    // The `searchable` modifier (List / NavigationStack): wrap the element with a
    // search field above its content (SearchableHelper.kt). Resolved before the
    // popover/decoration split because it owns the outermost Column; the element
    // then continues through the decoration path inside.
    resolveSearchable(effective.properties, logger)?.let { searchable ->
        BuildViewWithSearchable(effective, searchable, targeted, animator)
        return
    }
    if (effective.popover != null) {
        // PopoverHelper applies the outer half to the anchor Box itself and
        // routes the carrier through BuildViewWithDecorations.
        BuildViewWithPopover(effective, targeted, animator)
        return
    }
    // The `contextMenu` modifier (any view): a long-press floats a Material
    // DropdownMenu of the element's `contextMenu` action-item subviews (plus the
    // optional `contextMenuPreview` block) anchored to the element (ContextMenuHelper.kt).
    // Like popover, the wrapping Box takes the outer half and the carrier continues
    // through BuildViewWithDecorations inside. Requires at least one menu item (an
    // Apple context menu is its action list; a preview alone is not one). (Searchable/
    // popover above take precedence in the rare same-element combo, as with other combos.)
    if (effective.contextMenu?.isNotEmpty() == true) {
        BuildViewWithContextMenu(effective, targeted, animator)
        return
    }
    // The `swipeActions` modifier (List rows): a horizontal swipe reveals the row's
    // leading/trailing action Buttons; tapping one fires its actionID, and a full
    // swipe of an `allowsFullSwipe` edge fires that edge's first Button (SwipeActionsHelper.kt).
    // Like contextMenu, the wrapper takes the outer half and the carrier continues
    // through BuildViewWithDecorations inside. (contextMenu above takes precedence in the
    // rare same-row combo, as with the other modifier combos.)
    if (effective.swipeActions?.isNotEmpty() == true) {
        BuildViewWithSwipeActions(effective, targeted, animator)
        return
    }
    // The `safeAreaInset` modifier: place a view in the safe area on an edge, the content taking
    // the rest (SafeAreaHelper.kt). The wrapper owns the outer modifier; the element continues
    // through BuildViewWithDecorations inside, like the other wrapping modifiers.
    if (effective.safeAreaInset != null) {
        BuildViewWithSafeAreaInset(effective, targeted, animator)
        return
    }
    BuildViewWithDecorations(effective, targeted.applyOuterProperties(effective.properties, logger, animator), animator)
}

/**
 * [element] with the host's runtime overrides merged in - the Android analog of
 * Apple's views reading the mutated `validatedProperties` plus the
 * `applyDynamicSubviews` merge in `ActionUIRegistry.buildView`:
 *
 *   * **Property overrides** ([com.abracode.actionui.Common.ViewModel.propertyOverrides],
 *     written by `ActionUIModel.setElementProperty`) layer over the authored
 *     `properties`.
 *   * **Structural mutations** ([com.abracode.actionui.Common.ViewModel.dynamicSubviews],
 *     written by `WindowModel.insertElement` / `insertRow` / `removeElement`)
 *     replace the `children` / `destinations` / `rows` container the host has
 *     mutated. The declaring view's existing container read then sees the live
 *     list with no per-view wiring.
 *
 * Reading both snapshot maps subscribes this composition, so a host mutation
 * recomposes the element. Identity when the element has no registered ViewModel
 * or no overrides (the overwhelmingly common case).
 */
@Composable
private fun effectiveElement(element: ActionUIElement): ActionUIElement {
    if (element.id <= 0) return element
    val viewModel = LocalWindowModel.current?.viewModels?.get(element.id) ?: return element
    val overrides = viewModel.propertyOverrides
    val dynamic = viewModel.dynamicSubviews
    if (overrides.isEmpty() && dynamic.isEmpty()) return element
    return element.copy(
        properties = if (overrides.isEmpty()) element.properties
            else mergeProperties(element.properties, overrides),
        children = dynamic.flatContainer("children") ?: element.children,
        destinations = dynamic.flatContainer("destinations") ?: element.destinations,
        rows = dynamic.rowsContainer("rows") ?: element.rows,
    )
}

/** A flat-container override (`children` / `destinations`) from [dynamicSubviews], or null. */
@Suppress("UNCHECKED_CAST")
private fun Map<String, Any>.flatContainer(key: String): List<ActionUIElement>? =
    this[key] as? List<ActionUIElement>

/** The `rows` 2-D override from [dynamicSubviews], or null. */
@Suppress("UNCHECKED_CAST")
private fun Map<String, Any>.rowsContainer(key: String): List<List<ActionUIElement>>? =
    this[key] as? List<List<ActionUIElement>>

/** [overrides] layered over [authored], later writes winning per key. */
internal fun mergeProperties(
    authored: JsonObject?,
    overrides: Map<String, JsonElement>,
): JsonObject = JsonObject(
    buildMap {
        authored?.forEach { (key, value) -> put(key, value) }
        putAll(overrides)
    }
)

/**
 * Composes the element's `overlay` / `background` decoration subviews around
 * it (see [BuildViewWithModifiers]); the exact `BuildView` pass-through, plus
 * the inner property half, for the undecorated element. [modifier] must
 * already carry the parent data and the outer property half.
 */
@Composable
internal fun ActionUIViewConstruction.BuildViewWithDecorations(
    element: ActionUIElement,
    modifier: Modifier,
    animator: ElementAnimator? = null,
) {
    val logger = LocalActionUILogger.current
    // Captured here (in composition) so the inner-property appliers can resolve
    // Apple semantic color names to adaptive Material roles - see applyInnerProperties.
    val colorScheme = MaterialTheme.colorScheme
    val overlayElement = element.overlay
    val backgroundElement = element.background
    if (overlayElement == null && backgroundElement == null) {
        BuildView(element, modifier.applyInnerProperties(element.properties, logger, animator, colorScheme))
        return
    }

    // The Box sizes to the element alone (matchParentSize children are
    // excluded from its measurement), so decorations never change layout.
    Box(modifier) {
        backgroundElement?.let {
            ElementContent(it, logger, decorationModifier(element.properties, "backgroundAlignment", it, logger))
        }
        BuildView(element, Modifier.applyInnerProperties(element.properties, logger, animator, colorScheme))
        overlayElement?.let {
            ElementContent(it, logger, decorationModifier(element.properties, "overlayAlignment", it, logger))
        }
    }
}

/**
 * Sizes a decoration against the carrier's box and positions it by the
 * alignment property. SwiftUI *proposes* the carrier's size and the decoration
 * may refuse it; Compose constraints are hard caps, so the refusal must be
 * read off the decoration itself:
 *
 *   * No fixed `frame` -> the decoration accepts the proposal: measured with
 *     the carrier's box as its bounds, so a greedy bare shape (`Capsule`,
 *     `RoundedRectangle` - `fillMaxSize`, see `ShapeView.kt`) fills the
 *     decorated box exactly. The badge/card background idiom.
 *   * A fixed `frame` -> the decoration refuses: measured unbounded so its own
 *     size wins and may overflow the carrier, positioned by the alignment
 *     (a 56dp `Circle` behind a 44dp `Text` sticks out, as on Apple). The
 *     oversized-badge idiom. (Greedy `fillMaxSize` content cannot resolve
 *     against unbounded constraints, which is why this path is opt-in by
 *     frame rather than the default.)
 */
private fun BoxScope.decorationModifier(
    properties: JsonObject?,
    key: String,
    decoration: ActionUIElement,
    logger: ActionUILogger?,
): Modifier {
    val alignment = resolveDecorationAlignment(properties, key, logger)
    val frame = decoration.properties?.get("frame") as? JsonObject
    val hasFixedFrame = frame != null && (frame["width"] != null || frame["height"] != null)
    return Modifier.matchParentSize().wrapContentSize(alignment, unbounded = hasFixedFrame)
}

/**
 * Resolves `overlayAlignment` / `backgroundAlignment` with Apple's
 * `resolveAlignment` behavior (`View.swift`): SwiftUI alignment vocabulary
 * (`center`, the four edges - centered on the cross axis - and the four
 * corners), defaulting to `center` when absent, warn-and-center when unknown.
 */
internal fun resolveDecorationAlignment(
    properties: JsonObject?,
    key: String,
    logger: ActionUILogger?,
): Alignment {
    val name = properties?.stringProperty(key) ?: return Alignment.Center
    parseAlignment(name)?.let { return it }
    logger?.log(
        "Unknown alignment '$name' for property '$key'. Defaulting to 'center'.",
        LoggerLevel.warning,
    )
    return Alignment.Center
}
