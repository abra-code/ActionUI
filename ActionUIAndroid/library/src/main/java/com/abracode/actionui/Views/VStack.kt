package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

object VStack : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val spacing = element.properties?.get("spacing")?.jsonPrimitive?.doubleOrNull
        Column(
            modifier = modifier,
            verticalArrangement = spacing
                ?.let { Arrangement.spacedBy(it.dp) }
                ?: Arrangement.Top
        ) {
            element.children.orEmpty().forEach { child ->
                ActionUIRegistry.lookup(child.type)?.BuildView(child, Modifier)
            }
        }
    }
}
