package com.abracode.actionui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
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
import com.abracode.actionui.Helpers.DescriptionLoad
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.ToolbarHost
import com.abracode.actionui.Helpers.WindowDialogHost
import com.abracode.actionui.Helpers.WindowModalHost
import com.abracode.actionui.Helpers.classifyLoadableSource
import com.abracode.actionui.Helpers.hasRootToolbarChrome
import com.abracode.actionui.Helpers.loadLocalDescription
import com.abracode.actionui.Helpers.loadRemoteDescription
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
        // Key the window model on the source text: the element is re-decoded each
        // recomposition (a fresh but structurally identical instance), so it is not
        // a stable remember key.
        RenderWindow(element, windowKey = jsonString, modifier, logger, windowUUID)
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
     * Loads a JSON UI description from a `url` / `filePath` / bundle `name` [source]
     * and renders it as this window's **root** - the Android counterpart of Apple's
     * scene-level `LoadableWindowGroup` (`ActionUI/Scenes/LoadableWindowGroup.swift`)
     * and the `isContentView == true` branch of `FileLoadableView` /
     * `RemoteLoadableView`.
     *
     * Unlike the embedded [com.abracode.actionui.Views.LoadableView] element (which
     * *merges* its loaded tree into the current window as a sub-view), this builds a
     * **fresh** [com.abracode.actionui.Common.WindowModel] whose root *is* the loaded
     * element ([ActionUIModel.loadDescription]) - true root replacement, so the
     * loaded document owns the window and the value/state API addresses it directly.
     *
     * The source is classified by Apple's heuristics ([classifyLoadableSource]): a
     * `url` ([LoadableSource.Remote]) loads **asynchronously** off the main thread
     * (a [CircularProgressIndicator] shows while in flight, an error message on
     * failure; requires the `INTERNET` permission); a bundle `name` or `filePath`
     * loads synchronously. The read + decode is shared with the embedded element via
     * [DescriptionLoad].
     *
     * Not yet ported from the Apple scene: the window-level modal / dialog chrome
     * (`WindowModalView`) that `isContentView == true` also attaches - it awaits the
     * Android modal/dialog subsystem. See `Private/Android_Porting_Notes.md`.
     */
    @Composable
    fun RenderSource(
        source: String,
        modifier: Modifier = Modifier,
        logger: ActionUILogger = defaultLogger,
        windowUUID: String = "",
    ) {
        val assets = LocalContext.current.assets
        val classified = remember(source) { classifyLoadableSource(source) }

        // Remote loads async (spinner -> root/error); local loads synchronously.
        // `null` is the in-flight state. Nothing is registered until a Loaded result
        // is handed to RenderWindow (which owns the fresh window model).
        val loaded: DescriptionLoad? = if (classified is LoadableSource.Remote) {
            produceState<DescriptionLoad?>(null, classified) {
                value = null
                value = loadRemoteDescription(classified, json, logger)
            }.value
        } else {
            remember(classified) { loadLocalDescription(classified, assets, json, logger) }
        }

        when (loaded) {
            null -> Box(
                modifier.fillMaxWidth().padding(16.dp),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            is DescriptionLoad.Loaded ->
                RenderWindow(loaded.element, windowKey = loaded.element, modifier, logger, windowUUID)

            is DescriptionLoad.Failed -> SourceError("Failed to load view: ${loaded.message}", modifier)
            is DescriptionLoad.NoSource -> SourceError("No valid source provided", modifier)
            is DescriptionLoad.Deferred -> M3Text(
                loaded.message,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = modifier.padding(16.dp),
            )
        }
    }

    /**
     * Builds + registers a window model for [element] and renders its root. The
     * model is built once per [windowKey] (the caller supplies a stable key - the
     * source text for [Render], the loaded element instance for [RenderSource] -
     * since [element] itself may be a fresh instance each recomposition).
     * Registration in [ActionUIModel.loadDescription] makes the model resolvable
     * synchronously (before effects run); the [DisposableEffect] tears it down when
     * the window leaves the composition. The `expected` guard means a document swap
     * that already re-registered a new model under the same id is not evicted by the
     * old window's disposal.
     */
    @Composable
    private fun RenderWindow(
        element: ActionUIElement,
        windowKey: Any?,
        modifier: Modifier,
        logger: ActionUILogger,
        windowUUID: String,
    ) {
        val windowModel = remember(windowUUID, windowKey) {
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
            // Window-level overlays (the Android counterpart of Apple wrapping a
            // content-view root in WindowModalView). Both render nothing until a
            // host handler presents one: a dialog (alert / confirmationDialog) or a
            // modal (sheet / fullScreenCover).
            WindowDialogHost(windowModel)
            WindowModalHost(windowModel)
        }
    }

    @Composable
    private fun SourceError(message: String, modifier: Modifier) {
        M3Text(message, color = MaterialTheme.colorScheme.error, modifier = modifier.padding(16.dp))
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
