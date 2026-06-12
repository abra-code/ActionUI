package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment

/**
 * Grouped form layout. Mirror of the Apple `Form` element
 * (`ActionUI/Views/Form.swift`), which wraps `SwiftUI.Form` - a leading-aligned,
 * vertically grouped list of controls (typically `Section`s, `TextField`s,
 * `Toggle`s, `Picker`s).
 *
 * Rendered as a leading-aligned [Column] of its `children`, each built through
 * the registry with its inherited text-style environment and universal
 * modifiers. As in [VStack], a child `Spacer` flexes by taking remaining space.
 *
 * **Divergences from SwiftUI (documented).**
 *   * **Scrolling.** SwiftUI's `Form` scrolls on its own. A Compose container
 *     that scrolls cannot be measured with an unbounded main axis, which a
 *     `Form` nested in another vertical scroller (e.g. the demo host) would hit.
 *     So `Form` is a plain `Column`; wrap it in a `ScrollView` for scrolling -
 *     the same stance the renderer takes elsewhere (`LazyVStack` carries its own
 *     bounded viewport, the demo host supplies the outer scroll).
 *   * **Material grouping/inset styling** (section backgrounds, separators,
 *     insets) is not replicated; on Android a `Form` is effectively a
 *     leading-aligned vertical stack. A small default row spacing approximates
 *     the visual grouping.
 */
object Form : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        Column(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(DEFAULT_ROW_SPACING),
            horizontalAlignment = Alignment.Start,
        ) {
            element.children.orEmpty().forEach { child ->
                val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                val childModifier = buildChildModifier(child.properties, logger)
                    .let { if (child.type == "Spacer") it.weight(1f) else it }
                ProvideTextStyleEnvironment(child.properties, logger) {
                    builder.BuildViewWithModifiers(child, childModifier)
                }
            }
        }
    }

    /** Approximates SwiftUI Form's grouped row spacing (no exact Material analog). */
    private val DEFAULT_ROW_SPACING = 8.dp
}
