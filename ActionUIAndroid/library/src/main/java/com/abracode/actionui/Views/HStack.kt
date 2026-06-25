package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis
import com.abracode.actionui.Common.parseRowAlignment
import com.abracode.actionui.Common.stackChild
import com.abracode.actionui.Common.stackChildDataFor
import com.abracode.actionui.Common.stackMeasurePolicy
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

object HStack : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val spacing = (props?.get("spacing")?.jsonPrimitive?.doubleOrNull ?: 0.0).toFloat().dp
        // SwiftUI HStack default alignment is .center - match it (Compose's own
        // Row default would be Top).
        val verticalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseRowAlignment(it, logger) }
            ?: Alignment.CenterVertically
        CompositionLocalProvider(LocalStackAxis provides StackAxis.Horizontal) {
            // Custom layout (StackLayout.kt) so the HStack reproduces SwiftUI's
            // distribution - inflexible children reserve their space, flexible
            // ones split the remainder - rather than Compose Row's, which lets a
            // greedy child (a TextField) starve a compact sibling (a Picker).
            Layout(
                modifier = modifier,
                content = {
                    // Template (data-driven) mode wins over children, as on Apple:
                    // one substituted instance per row (Helpers/TemplateHelper.kt).
                    val template = element.template
                    if (template != null) {
                        templateRows(element.id).forEachIndexed { rowIndex, row ->
                            TemplateHelper.BuildTemplateRow(
                                template = template, row = row, parentID = element.id, rowIndex = rowIndex,
                            )
                        }
                    } else element.children.orEmpty().forEach { child ->
                        val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                        // Wrap each child in a Box carrying its main-axis flexibility as
                        // parent data. The Box (not the element's own modifier) is the node
                        // the measure policy sees, so the data survives even when the element
                        // wraps itself in another layout node (e.g. a SelectionContainer for
                        // `textSelection`) that would otherwise hide the parent data.
                        Box(
                            modifier = Modifier.stackChild(stackChildDataFor(child, horizontal = true)),
                            propagateMinConstraints = true,
                        ) {
                            ProvideTextStyleEnvironment(child.properties, logger) {
                                builder.BuildViewWithModifiers(child, Modifier)
                            }
                        }
                    }
                },
                measurePolicy = stackMeasurePolicy(
                    horizontal = true,
                    spacing = spacing,
                    verticalAlignment = verticalAlignment,
                    horizontalAlignment = null,
                ),
            )
        }
    }
}
