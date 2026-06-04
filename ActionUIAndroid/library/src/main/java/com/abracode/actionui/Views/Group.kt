package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment

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
 * resolved `applyCommonProperties`) is composed onto each child ahead of that
 * child's own modifier, reproducing that semantics. For the common empty-modifier
 * Group this is a clean passthrough.
 *
 * Each child is wrapped in [ProvideTextStyleEnvironment] so its own
 * `font`/`foregroundStyle`/`tint` apply, consistent with the layout containers.
 *
 * **Deferred vs. Apple.** Like the lazy stacks, the data-driven `template` mode
 * (one instance per row via `setElementRows`) needs the `ViewModel`/state layer
 * that has not landed yet; only static `children` are rendered. Children of a
 * Group also receive only the base `applyCommonProperties` modifier, so the
 * scope-restricted `weight`/`align` child modifiers are not propagated through a
 * Group (same limitation as the lazy stacks). See `Private/Android_Porting_Notes.md`.
 */
object Group : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        element.children.orEmpty().forEach { child ->
            val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
            val childModifier = modifier.then(Modifier.applyCommonProperties(child.properties, logger))
            ProvideTextStyleEnvironment(child.properties, logger) {
                builder.BuildView(child, childModifier)
            }
        }
    }
}
