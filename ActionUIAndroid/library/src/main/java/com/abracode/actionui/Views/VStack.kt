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
import com.abracode.actionui.Common.parseColumnAlignment
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

object VStack : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI VStack default alignment is .center — match it; Compose's
        // own Column default is Start.
        val horizontalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseColumnAlignment(it, logger) }
            ?: Alignment.CenterHorizontally
        Column(
            modifier = modifier,
            verticalArrangement = spacing
                ?.let { Arrangement.spacedBy(it.dp) }
                ?: Arrangement.Top,
            horizontalAlignment = horizontalAlignment
        ) {
            element.children.orEmpty().forEach { child ->
                val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                builder.BuildView(child, buildChildModifier(child.properties, logger))
            }
        }
    }
}
