package com.abracode.actionui.Views

import android.content.res.AssetManager
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.PlatformFilter
import com.abracode.actionui.Common.WindowModel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.LoadableFormat
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.classifyLoadableSource
import com.abracode.actionui.Helpers.resolveLoadableSource
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.io.File
import java.io.IOException

/**
 * Loads a JSON UI description from a source and renders it inline - the Android
 * port of the Apple `LoadableView` element (`ActionUI/Views/LoadableView.swift`),
 * a "dynamic include" that fetches a sub-document and renders it as a nested
 * `ActionUIView`.
 *
 * **Sources** (Apple's `url` > `filePath` > `name` priority, resolved by
 * [resolveLoadableSource]; the active source is also the element's runtime
 * [ActionUIValueType.STRING] value, so a host can swap it via
 * `ActionUIModel.setElementValue`):
 *   * `name` - a bundle resource, read from the app's `assets/` (`.json` appended
 *     when the name has no extension). **Shipped.**
 *   * `filePath` - an absolute filesystem path (`file://` accepted). **Shipped.**
 *   * `url` - a remote `http(s)` document. **Deferred** to a later
 *     `RemoteLoadableView` chunk (it needs async loading + the INTERNET
 *     permission); this case warn-and-skips with a placeholder, mirroring Apple's
 *     split into a synchronous `FileLoadableView` and an async `RemoteLoadableView`.
 *
 * **Rendering.** The loaded JSON is decoded the same way as the window root
 * ([Json] + the Android [PlatformFilter], so `:android` keys and platform-only
 * children resolve), its [com.abracode.actionui.Common.ViewModel] pool is **merged
 * into the current window** ([WindowModel.loadSubDescription]) so the value/state
 * API reaches the loaded controls by id, then its root is built through the
 * registry like any child. The loaded description must use ids unique within the
 * combined tree (Apple documents the same assumption).
 *
 * **`viewDidLoadActionID`** fires once after a new source loads successfully (keyed
 * to the source, so a recomposition for the same source does not re-fire), matching
 * Apple's dedup.
 *
 * **Deferred vs. Apple:** remote `url` (above), `.plist` sources (no Android
 * property-list parser - [LoadableFormat.PLIST] warn-and-skips), and the window
 * content-view role (`isContentView` window-modal wrapping) which has no Android
 * modal layer yet. See `Private/Android_Porting_Notes.md`.
 */
object LoadableView : ActionUIViewConstruction {

    override val valueType = ActionUIValueType.STRING

    /** Seeds the value bridge with the authored source (url > filePath > name). */
    override fun initialValue(element: ActionUIElement): Any? =
        resolveLoadableSource(null, element.properties) ?: ""

    private val json: Json = Json { ignoreUnknownKeys = true }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val assets = LocalContext.current.assets
        val windowModel = LocalWindowModel.current
        val props = element.properties

        // The live source: the runtime value when a host has set one, else authored.
        val runtimeValue = windowModel?.viewModels?.get(element.id)?.value as? String
        val source = resolveLoadableSource(runtimeValue, props)
        val classified = remember(source) { classifyLoadableSource(source) }

        // Load + parse + merge once per (window, source). Synchronous, matching
        // Apple's FileLoadableView init-time load; remembered so it does not re-run
        // on unrelated recompositions.
        val outcome = remember(windowModel, classified) {
            loadLoadable(classified, assets, json, windowModel, logger)
        }

        // Fire viewDidLoadActionID once per successfully loaded source.
        val viewDidLoadActionID = props?.stringProperty("viewDidLoadActionID")
        if (outcome is LoadOutcome.Loaded && viewDidLoadActionID != null) {
            LaunchedEffect(source) {
                ActionUIModel.actionHandler(
                    actionID = viewDidLoadActionID,
                    windowUUID = windowModel?.windowUUID ?: "",
                    viewID = element.id,
                    viewPartID = 0,
                    context = null,
                )
            }
        }

        when (outcome) {
            is LoadOutcome.Loaded -> {
                val loaded = outcome.element
                val builder = ActionUIRegistry.lookup(loaded.type)
                if (builder == null) {
                    ErrorText("Unknown element type: ${loaded.type}", modifier)
                    return
                }
                val childModifier = modifier.then(Modifier.applyCommonProperties(loaded.properties, logger))
                ProvideTextStyleEnvironment(loaded.properties, logger) {
                    builder.BuildView(loaded, childModifier)
                }
            }
            is LoadOutcome.Failed -> ErrorText("Failed to load view: ${outcome.message}", modifier)
            is LoadOutcome.NoSource -> ErrorText("No valid source provided", modifier)
            is LoadOutcome.Deferred -> M3Text(
                outcome.message,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = modifier.padding(16.dp),
            )
        }
    }

    @Composable
    private fun ErrorText(message: String, modifier: Modifier) {
        M3Text(message, color = MaterialTheme.colorScheme.error, modifier = modifier.padding(16.dp))
    }
}

/** The result of resolving + loading a [LoadableSource]. */
private sealed interface LoadOutcome {
    /** Parsed and (if a window is present) registered; ready to render. */
    data class Loaded(val element: ActionUIElement) : LoadOutcome
    /** A source was present but could not be read/parsed; shows [message] in error color. */
    data class Failed(val message: String) : LoadOutcome
    /** No usable source. */
    object NoSource : LoadOutcome
    /** A recognized but not-yet-supported source (remote url / plist); shows [message]. */
    data class Deferred(val message: String) : LoadOutcome
}

/**
 * Reads, parses, and registers a [source] description. Pure of Compose; does
 * synchronous IO for the local cases (matching Apple's `FileLoadableView`). Remote
 * and plist sources are deferred (warn + [LoadOutcome.Deferred]).
 */
private fun loadLoadable(
    source: LoadableSource,
    assets: AssetManager,
    json: Json,
    windowModel: WindowModel?,
    logger: ActionUILogger,
): LoadOutcome = when (source) {
    is LoadableSource.None -> LoadOutcome.NoSource

    is LoadableSource.Remote -> {
        logger.log(
            "LoadableView: remote URL loading is not supported yet on Android (deferred to " +
                "RemoteLoadableView). Source: ${source.url}",
            LoggerLevel.warning
        )
        LoadOutcome.Deferred("Remote URL loading is not supported yet on Android")
    }

    is LoadableSource.BundleName -> {
        if (source.format == LoadableFormat.PLIST) deferredPlist(source.name, logger)
        else {
            val path = if (source.name.contains('.')) source.name else "${source.name}.json"
            try {
                val text = assets.open(path).bufferedReader().use { it.readText() }
                parseAndRegister(text, json, windowModel, logger)
            } catch (e: IOException) {
                logger.log("LoadableView: bundle resource '$path' not found in assets/: ${e.message}", LoggerLevel.error)
                LoadOutcome.Failed("Resource '${source.name}' not found")
            }
        }
    }

    is LoadableSource.FilePath -> {
        if (source.format == LoadableFormat.PLIST) deferredPlist(source.path, logger)
        else try {
            val text = File(source.path).readText()
            parseAndRegister(text, json, windowModel, logger)
        } catch (e: IOException) {
            logger.log("LoadableView: cannot read file '${source.path}': ${e.message}", LoggerLevel.error)
            LoadOutcome.Failed("Cannot read file: ${source.path}")
        }
    }
}

/** Decodes [text] (with the Android platform filter) and merges it into [windowModel]. */
private fun parseAndRegister(
    text: String,
    json: Json,
    windowModel: WindowModel?,
    logger: ActionUILogger,
): LoadOutcome {
    val element = try {
        val raw = json.parseToJsonElement(text)
        val filtered = PlatformFilter.Android.withLogger(logger).filter(raw)
        json.decodeFromJsonElement(ActionUIElement.serializer(), filtered)
    } catch (e: SerializationException) {
        logger.log("LoadableView: failed to parse loaded description: ${e.message}", LoggerLevel.error)
        return LoadOutcome.Failed("Failed to parse description")
    } catch (e: IllegalArgumentException) {
        logger.log("LoadableView: failed to decode loaded description: ${e.message}", LoggerLevel.error)
        return LoadOutcome.Failed("Failed to decode description")
    }
    windowModel?.loadSubDescription(element)
    return LoadOutcome.Loaded(element)
}

/** Warn-and-skip for a `.plist` source: no Android property-list parser yet. */
private fun deferredPlist(source: String, logger: ActionUILogger): LoadOutcome {
    logger.log(
        "LoadableView: '.plist' sources are not supported on Android (no property-list parser); " +
            "use a JSON description. Source: $source",
        LoggerLevel.warning
    )
    return LoadOutcome.Deferred("Property-list (.plist) sources are not supported on Android; use JSON")
}
