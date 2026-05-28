package com.abracode.actionui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import kotlinx.serialization.json.Json

object ActionUI {

    private val json: Json = Json {
        ignoreUnknownKeys = true
    }

    @Composable
    fun Render(jsonString: String, modifier: Modifier = Modifier) {
        val element = json.decodeFromString<ActionUIElement>(jsonString)
        ActionUIRegistry.lookup(element.type)?.BuildView(element, modifier)
    }

    @Composable
    fun RenderAsset(assetPath: String, modifier: Modifier = Modifier) {
        val context = LocalContext.current
        val jsonString = context.assets.open(assetPath).bufferedReader().use { it.readText() }
        Render(jsonString, modifier)
    }
}
