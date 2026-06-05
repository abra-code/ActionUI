package com.abracode.actionui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.PlatformFilter
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.ToolbarHost
import com.abracode.actionui.Helpers.hasRootToolbarChrome
import com.abracode.actionui.Helpers.numberProperty
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

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
            RenderRoot(element, builder, modifier, logger)
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

    /**
     * Renders the document's root [element]. When the root declares a `toolbar` or
     * a `navigationTitle` (see [hasRootToolbarChrome]) it is wrapped in a
     * [ToolbarHost] - a `Scaffold` + `TopAppBar` / `BottomAppBar` - so a top-level
     * `VStack` / `List` / etc. carries the native navigation chrome the same way a
     * `NavigationStack` screen does (Android Porting Notes 29/32). A
     * `NavigationStack` root is excluded (it owns a host per navigation screen).
     *
     * The root `Scaffold` self-bounds like every viewport element here
     * ([[android-bounded-height-scroll]]): an explicit `frame.height` bounds it,
     * else [DEFAULT_ROOT_SCREEN_EXTENT] keeps a scrolling host from leaving it
     * unbounded. The element's common properties decorate the body (as on a
     * navigation screen), so `frame.height` also flows to the content; the modifier
     * here only supplies the Scaffold's finite height.
     */
    @Composable
    private fun RenderRoot(
        element: ActionUIElement,
        builder: ActionUIViewConstruction,
        modifier: Modifier,
        logger: ActionUILogger,
    ) {
        if (!hasRootToolbarChrome(element)) {
            ProvideTextStyleEnvironment(element.properties, logger) {
                builder.BuildView(element, modifier.applyCommonProperties(element.properties, logger))
            }
            return
        }

        val frameHeight = (element.properties?.get("frame") as? JsonObject)
            ?.numberProperty("height")?.toFloat()?.dp
        val hostModifier = modifier.height(frameHeight ?: DEFAULT_ROOT_SCREEN_EXTENT)

        ToolbarHost(element, logger, modifier = hostModifier) { inner ->
            Box(Modifier.padding(inner)) {
                ProvideTextStyleEnvironment(element.properties, logger) {
                    builder.BuildView(element, Modifier.applyCommonProperties(element.properties, logger))
                }
            }
        }
    }

    /** Scaffold height for a root toolbar screen with no explicit `frame.height`. */
    private val DEFAULT_ROOT_SCREEN_EXTENT: Dp = 560.dp
}
