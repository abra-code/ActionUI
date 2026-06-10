package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.WindowModel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.DescriptionLoad
import com.abracode.actionui.Helpers.LoadableFormat
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.classifyLoadableSource
import com.abracode.actionui.Helpers.loadLocalDescription
import com.abracode.actionui.Helpers.loadRemoteDescription
import com.abracode.actionui.Helpers.resolveLoadableSource
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.Json

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
 *   * `url` - a remote `http(s)` document, fetched **asynchronously** off the main
 *     thread with a [CircularProgressIndicator] while in flight and an error
 *     message on failure. Mirrors Apple's async `RemoteLoadableView`. Requires the
 *     `INTERNET` permission (declared in the library manifest).
 *   * `name` - a bundle resource, read **synchronously** from the app's `assets/`
 *     (`.json` appended when the name has no extension). Mirrors `FileLoadableView`.
 *   * `filePath` - an absolute filesystem path (`file://` accepted), read
 *     synchronously.
 *
 * The read + decode is shared with [com.abracode.actionui.ActionUI.RenderSource]
 * (see [com.abracode.actionui.Helpers.DescriptionLoad]); this element supplies the
 * **sub-view** registration policy: the loaded
 * [com.abracode.actionui.Common.ViewModel] pool is **merged into the current
 * window** ([WindowModel.loadSubDescription]) so the value/state API reaches the
 * loaded controls by id, then the root is built through the registry like any
 * child. The loaded description must use ids unique within the combined tree
 * (Apple documents the same assumption). This is Apple's `isContentView == false`
 * branch; the root-replacing `isContentView == true` branch is
 * [com.abracode.actionui.ActionUI.RenderSource].
 *
 * **`viewDidLoadActionID`** fires once after a new source loads successfully (keyed
 * to the source, so a recomposition for the same source does not re-fire), matching
 * Apple's dedup.
 *
 * **Deferred vs. Apple:** `.plist` sources (no Android property-list parser -
 * [LoadableFormat.PLIST] warn-and-skips). See `Private/Android_Porting_Notes.md`.
 */
object LoadableView : ActionUIViewConstruction {

    override val valueType = ActionUIValueType.STRING

    /** Seeds the value bridge with the authored source (url > filePath > name). */
    override fun initialValue(element: ActionUIElement): Any? =
        resolveLoadableSource(null, element.properties) ?: ""

    // Shared document decoder config (Foundation-leniency parity; see Common/ActionUIJson).
    private val json: Json = ActionUIJson

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

        // Remote loads async (spinner -> content/error); local loads synchronously
        // in `remember` (matching Apple's FileLoadableView init-time load, no flash).
        // `null` is the in-flight state. The loaded sub-tree is merged into the
        // current window as it arrives (off the render path), so the value/state
        // API reaches it by id.
        val outcome: DescriptionLoad? = if (classified is LoadableSource.Remote) {
            produceState<DescriptionLoad?>(null, classified, windowModel) {
                value = null
                value = loadRemoteDescription(classified, json, logger).also { mergeIntoWindow(it, windowModel) }
            }.value
        } else {
            remember(windowModel, classified) {
                loadLocalDescription(classified, assets, json, logger).also { mergeIntoWindow(it, windowModel) }
            }
        }

        // Fire viewDidLoadActionID once per successfully loaded source.
        val viewDidLoadActionID = props?.stringProperty("viewDidLoadActionID")
        if (outcome is DescriptionLoad.Loaded && viewDidLoadActionID != null) {
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
            null -> Box(
                modifier.fillMaxWidth().padding(16.dp),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            is DescriptionLoad.Loaded -> {
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

            is DescriptionLoad.Failed -> ErrorText("Failed to load view: ${outcome.message}", modifier)
            is DescriptionLoad.NoSource -> ErrorText("No valid source provided", modifier)
            is DescriptionLoad.Deferred -> M3Text(
                outcome.message,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = modifier.padding(16.dp),
            )
        }
    }

    /** Merges a successfully loaded sub-tree into [windowModel] (no-op otherwise). */
    private fun mergeIntoWindow(outcome: DescriptionLoad, windowModel: WindowModel?) {
        if (outcome is DescriptionLoad.Loaded) windowModel?.loadSubDescription(outcome.element)
    }

    @Composable
    private fun ErrorText(message: String, modifier: Modifier) {
        M3Text(message, color = MaterialTheme.colorScheme.error, modifier = modifier.padding(16.dp))
    }
}
