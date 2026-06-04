package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Common.parseRowAlignment
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

object HStack : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI HStack default alignment is .center - match it so a single
        // JSON file behaves the same on both platforms when alignment is
        // omitted. Compose's own Row default is Top.
        val verticalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseRowAlignment(it, logger) }
            ?: Alignment.CenterVertically
        CompositionLocalProvider(LocalStackAxis provides StackAxis.Horizontal) {
            Row(
                modifier = modifier,
                horizontalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Start,
                verticalAlignment = verticalAlignment
            ) {
                element.children.orEmpty().forEach { child ->
                    val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                    // Spacer flexes by consuming remaining main-axis space; weight is
                    // RowScope-restricted, so the container applies it here (see Spacer.kt).
                    val childModifier = buildChildModifier(child.properties, logger)
                        .let { if (child.type == "Spacer") it.weight(1f) else it }
                    ProvideTextStyleEnvironment(child.properties, logger) {
                        builder.BuildView(child, childModifier)
                    }
                }
            }
        }
    }
}
