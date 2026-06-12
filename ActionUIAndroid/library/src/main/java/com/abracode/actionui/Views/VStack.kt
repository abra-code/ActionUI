package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Common.parseColumnAlignment
import com.abracode.actionui.Helpers.BuildViewWithPopover
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

object VStack : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI VStack default alignment is .center - match it; Compose's
        // own Column default is Start.
        val horizontalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseColumnAlignment(it, logger) }
            ?: Alignment.CenterHorizontally
        CompositionLocalProvider(LocalStackAxis provides StackAxis.Vertical) {
            Column(
                modifier = modifier,
                verticalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Top,
                horizontalAlignment = horizontalAlignment
            ) {
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
                    // Spacer flexes by consuming remaining main-axis space; weight is
                    // ColumnScope-restricted, so the container applies it here (see Spacer.kt).
                    val childModifier = buildChildModifier(child.properties, logger)
                        .let { if (child.type == "Spacer") it.weight(1f) else it }
                    ProvideTextStyleEnvironment(child.properties, logger) {
                        builder.BuildViewWithPopover(child, childModifier)
                    }
                }
            }
        }
    }
}
