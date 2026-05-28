package com.abracode.actionui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.PlatformFilter
import kotlinx.serialization.json.Json

object ActionUI {

    private val json: Json = Json {
        ignoreUnknownKeys = true
    }

    /**
     * Default logger used when callers don't supply one. Swap globally for
     * tests by assigning a different [ActionUILogger]; per-call overrides are
     * preferred for non-default behavior.
     */
    var defaultLogger: ActionUILogger = ConsoleLogger()

    @Composable
    fun Render(
        jsonString: String,
        modifier: Modifier = Modifier,
        logger: ActionUILogger = defaultLogger
    ) {
        val raw = json.parseToJsonElement(jsonString)
        val filtered = PlatformFilter.Android.withLogger(logger).filter(raw)
        val element = json.decodeFromJsonElement(ActionUIElement.serializer(), filtered)
        ActionUIRegistry.lookup(element.type)?.BuildView(element, modifier)
    }

    @Composable
    fun RenderAsset(
        assetPath: String,
        modifier: Modifier = Modifier,
        logger: ActionUILogger = defaultLogger
    ) {
        val context = LocalContext.current
        val jsonString = context.assets.open(assetPath).bufferedReader().use { it.readText() }
        Render(jsonString, modifier, logger)
    }
}
