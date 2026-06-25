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
import com.abracode.actionui.Common.parseColumnAlignment
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

object VStack : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val spacing = (props?.get("spacing")?.jsonPrimitive?.doubleOrNull ?: 0.0).toFloat().dp
        // SwiftUI VStack default alignment is .center - match it (Compose's own
        // Column default would be Start).
        val horizontalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseColumnAlignment(it, logger) }
            ?: Alignment.CenterHorizontally
        CompositionLocalProvider(LocalStackAxis provides StackAxis.Vertical) {
            // Custom layout (StackLayout.kt) so the VStack reproduces SwiftUI's
            // vertical distribution - inflexible children reserve their height,
            // flexible ones split the remainder - rather than Compose Column's.
            Layout(
                modifier = modifier,
                content = {
                    // Template (data-driven) mode wins over children, as on Apple.
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
                        // parent data (see HStack for why the Box, not the element modifier).
                        Box(
                            modifier = Modifier.stackChild(stackChildDataFor(child, horizontal = false)),
                            propagateMinConstraints = true,
                        ) {
                            ProvideTextStyleEnvironment(child.properties, logger) {
                                builder.BuildViewWithModifiers(child, Modifier)
                            }
                        }
                    }
                },
                measurePolicy = stackMeasurePolicy(
                    horizontal = false,
                    spacing = spacing,
                    verticalAlignment = null,
                    horizontalAlignment = horizontalAlignment,
                ),
            )
        }
    }
}
