package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.templateRows

/**
 * Transparent grouping container. Mirror of the Apple `Group` element
 * (`ActionUI/Views/Group.swift`), which wraps `SwiftUI.Group`.
 *
 * **No layout of its own (the load-bearing property).** A SwiftUI `Group` does
 * not lay out its children; whatever container encloses the Group arranges the
 * children as if they were declared inline. Compose has the same property for a
 * composable that emits several children without wrapping them in a layout node:
 * the emissions land in the *caller's* scope. So this builder simply iterates the
 * children and builds each one - when a Group sits inside a [VStack]/[HStack]/
 * [ZStack], its children are placed by that parent directly, matching SwiftUI.
 *
 * **Group modifiers apply to each child.** In SwiftUI a modifier attached to a
 * Group is applied to each of its subviews, not to a wrapping node. Because there
 * is no wrapping node here either, the group-level [modifier] (the Group's own
 * resolved common properties, fused by `BuildViewWithModifiers`) is composed onto each
 * child ahead of that child's own modifier, reproducing that semantics. For the
 * common empty-modifier Group this is a clean passthrough.
 *
 * Each child is wrapped in [ProvideTextStyleEnvironment] so its own
 * `font`/`foregroundStyle`/`tint` apply, consistent with the layout containers.
 *
 * The Group also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API) is
 * emitted into the caller's scope, each carrying the group-level [modifier] the
 * way static children do. See `Helpers/TemplateHelper.kt`.
 *
 * **Deferred vs. Apple.** Children of a Group receive only the base
 * `applyCommonProperties` modifier, so the scope-restricted `weight`/`align`
 * child modifiers are not propagated through a Group (same limitation as the
 * lazy stacks). See `Private/Android_Porting_Notes.md`.
 */
object Group : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        // Template (data-driven) mode wins over children, as on Apple.
        val template = element.template
        if (template != null) {
            templateRows(element.id).forEachIndexed { rowIndex, row ->
                TemplateHelper.BuildTemplateRow(
                    template = template, row = row, parentID = element.id, rowIndex = rowIndex,
                    baseModifier = modifier,
                )
            }
        } else element.children.orEmpty().forEach { child ->
            val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
            // The group-level modifier leads; BuildViewWithModifiers resolves
            // the child's own common properties after it.
            ProvideTextStyleEnvironment(child.properties, logger) {
                builder.BuildViewWithModifiers(child, modifier)
            }
        }
    }
}
