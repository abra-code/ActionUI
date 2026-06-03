package com.abracode.actionui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.PlatformFilter
import com.abracode.actionui.Common.applyCommonProperties
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

    /**
     * Renders [jsonString] for the window identified by [windowUUID].
     *
     * A [com.abracode.actionui.Common.WindowModel] is built once per document
     * (remembered, keyed by [windowUUID] + [jsonString]) and registered with
     * [ActionUIModel] for the lifetime of this composition, so host code can read
     * and write control values via `ActionUIModel.getElementValue(...)` /
     * `setElementValue(...)`. The model is exposed to the element tree through
     * [LocalWindowModel] so value-bearing controls bind to their
     * [com.abracode.actionui.Common.ViewModel].
     *
     * [windowUUID] defaults to the empty string: Android is single-window today,
     * and the value/state API uses the same default, so a single rendered
     * document needs no explicit id.
     */
    @Composable
    fun Render(
        jsonString: String,
        modifier: Modifier = Modifier,
        logger: ActionUILogger = defaultLogger,
        windowUUID: String = "",
    ) {
        val raw = json.parseToJsonElement(jsonString)
        val filtered = PlatformFilter.Android.withLogger(logger).filter(raw)
        val element = json.decodeFromJsonElement(ActionUIElement.serializer(), filtered)

        // Build + register the window model once per document. Registration in
        // loadDescription makes it resolvable synchronously (before effects run);
        // the DisposableEffect only tears it down when this window leaves the
        // composition. The `expected` guard means a document swap that already
        // re-registered a new model under the same id is not evicted by the old
        // window's disposal.
        val windowModel = remember(windowUUID, jsonString) {
            ActionUIModel.loadDescription(element, windowUUID, logger)
        }
        DisposableEffect(windowModel) {
            onDispose { ActionUIModel.unregisterWindow(windowUUID, expected = windowModel) }
        }

        val builder = ActionUIRegistry.lookup(element.type) ?: return
        CompositionLocalProvider(
            LocalActionUILogger provides logger,
            LocalWindowModel provides windowModel,
        ) {
            builder.BuildView(
                element,
                modifier.applyCommonProperties(element.properties, logger)
            )
        }
    }

    @Composable
    fun RenderAsset(
        assetPath: String,
        modifier: Modifier = Modifier,
        logger: ActionUILogger = defaultLogger,
        windowUUID: String = "",
    ) {
        val context = LocalContext.current
        val jsonString = context.assets.open(assetPath).bufferedReader().use { it.readText() }
        Render(jsonString, modifier, logger, windowUUID)
    }
}
