package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Common.parseAlignment
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.containerActionModifier
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Depth stack: children overlap in z-order, earlier children behind later ones.
 * Mirror of the Apple `ZStack` element (`ActionUI/Views/ZStack.swift`), which
 * wraps `SwiftUI.ZStack`.
 *
 * Rendered as a Compose [Box], the direct analog: a Box lays its children on top
 * of one another (declaration order is back-to-front, matching SwiftUI) and
 * positions them with a single `contentAlignment`.
 *
 * **Supported properties.**
 *   * `alignment` - how children are positioned within the stack, one of
 *     `topLeading`, `top`, `topTrailing`, `leading`, `center`, `trailing`,
 *     `bottomLeading`, `bottom`, `bottomTrailing` (SwiftUI vocabulary, resolved
 *     by [parseAlignment]). Defaults to `center`; an unrecognized value warns and
 *     falls back to center.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (applied
 *     via [modifier]) and per-child `align` (the [Box] overload of
 *     [buildChildModifier] lets an individual child override the stack alignment).
 *
 * Unlike [VStack]/[HStack], a ZStack has no layout axis, so it does not provide
 * [com.abracode.actionui.Common.LocalStackAxis]; a `Divider` nested directly in a
 * ZStack keeps the inherited orientation (horizontal by default), matching the
 * "no axis" nature of an overlap container.
 *
 * Like its Apple counterpart, the stack also supports the data-driven `template`
 * mode: when [ActionUIElement.template] is present, one substituted template
 * instance per row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the
 * rows API) is layered into the stack. See `Helpers/TemplateHelper.kt`.
 */
object ZStack : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val alignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull?.let { name ->
            parseAlignment(name) ?: run {
                logger.log(
                    "ZStack alignment '$name' must be one of topLeading, top, topTrailing, " +
                        "leading, center, trailing, bottomLeading, bottom, bottomTrailing; using center",
                    LoggerLevel.warning
                )
                null
            }
        } ?: Alignment.Center

        // The container tap wraps the chain from OUTSIDE (see containerActionModifier):
        // appending it would put the tap inside the padding, leaving a dead ring.
        Box(modifier = containerActionModifier(element, modifier), contentAlignment = alignment) {
            // Template (data-driven) mode wins over children, as on Apple:
            // one substituted instance per row. See Helpers/TemplateHelper.kt.
            val template = element.template
            if (template != null) {
                templateRows(element.id).forEachIndexed { rowIndex, row ->
                    TemplateHelper.BuildTemplateRow(
                        template = template, row = row, parentID = element.id, rowIndex = rowIndex,
                    )
                }
            } else element.children.orEmpty().forEach { child ->
                val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                ProvideTextStyleEnvironment(child.properties, logger) {
                    builder.BuildViewWithModifiers(child, buildChildModifier(child.properties, logger))
                }
            }
        }
    }
}
