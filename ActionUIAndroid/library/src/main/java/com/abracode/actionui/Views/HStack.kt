package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Common.parseRowAlignment
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

object HStack : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI HStack default alignment is .center — match it so a single
        // JSON file behaves the same on both platforms when alignment is
        // omitted. Compose's own Row default is Top.
        val verticalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseRowAlignment(it, logger) }
            ?: Alignment.CenterVertically
        Row(
            modifier = modifier,
            horizontalArrangement = spacing
                ?.let { Arrangement.spacedBy(it.dp) }
                ?: Arrangement.Start,
            verticalAlignment = verticalAlignment
        ) {
            element.children.orEmpty().forEach { child ->
                val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                builder.BuildView(child, buildChildModifier(child.properties, logger))
            }
        }
    }
}
