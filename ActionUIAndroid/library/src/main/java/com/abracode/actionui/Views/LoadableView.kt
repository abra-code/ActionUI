package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.LocalJSONContentOrigin
import com.abracode.actionui.Common.resolvedOrigin
import com.abracode.actionui.Common.uriHandlerFor
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.WindowModel
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.DescriptionLoad
import com.abracode.actionui.Helpers.LoadableFormat
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.classifyLoadableSource
import com.abracode.actionui.Helpers.loadLocalDescription
import com.abracode.actionui.Helpers.loadableNestingKey
import com.abracode.actionui.Helpers.loadableNestingRefusal
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
 * **Nesting:** a source that a LoadableView around this one already shows (a document
 * that loads itself, directly or through others), or one nested more than 16 deep, is
 * refused with "Failed to load view: ..." in the error color, by the same rule as Apple's
 * `LoadableNestingGuard` ([loadableNestingRefusal]). The sources of the LoadableViews
 * around one travel in [LocalLoadableSources]; siblings showing the same source stay
 * allowed. A refused source is never read.
 *
 * **Deferred vs. Apple:** `.plist` sources (no Android property-list parser -
 * [LoadableFormat.PLIST] warn-and-skips).
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
        val ownModel = windowModel?.viewModels?.get(element.id)
        val runtimeValue = ownModel?.value as? String
        val source = resolveLoadableSource(runtimeValue, props)
        val classified = remember(source) { classifyLoadableSource(source) }
        // The loaded content's origin: its source's, no more trusted than the content around it.
        val around = LocalJSONContentOrigin.current
        val origin = remember(classified, around) {
            resolvedOrigin(classified, around, element.id.takeIf { it > 0 })
        }

        // Refuse a source a LoadableView around this one shows, or a chain too deep, before
        // anything is read: a file or asset source loads during composition.
        val enclosing = LocalLoadableSources.current
        val nestingKey = remember(classified) { loadableNestingKey(classified) }
        val refusal = nestingKey?.let { loadableNestingRefusal(it, enclosing) }
        if (refusal != null) {
            LaunchedEffect(nestingKey, refusal) {
                logger.log("LoadableView: not loading $nestingKey: $refusal", LoggerLevel.error)
            }
            ErrorText("Failed to load view: $refusal", modifier)
            return
        }

        // Remote loads async (spinner -> content/error); local loads synchronously
        // in `remember` (matching Apple's FileLoadableView init-time load, no flash).
        // `null` is the in-flight state. The loaded sub-tree is merged into the
        // current window as it arrives (off the render path), so the value/state
        // API reaches it by id. Keyed on this view's own model too: a reload of the
        // content around it (or a window reload) removes the models this view's
        // content merged and gives this view a fresh model, so it merges again.
        val outcome: DescriptionLoad? = if (classified is LoadableSource.Remote) {
            produceState<DescriptionLoad?>(null, classified, windowModel, ownModel) {
                value = null
                value = mergeIntoWindow(loadRemoteDescription(classified, json, logger), windowModel, element.id, origin)
            }.value
        } else {
            remember(windowModel, classified, ownModel) {
                mergeIntoWindow(loadLocalDescription(classified, assets, json, logger), windowModel, element.id, origin)
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
                // BuildViewWithModifiers resolves the loaded element's common properties.
                // LoadableViews inside the loaded tree see this source among those around them.
                val inside = if (nestingKey != null) enclosing + nestingKey else enclosing
                // Its links in Markdown text open through LocalUriHandler, which asks the trust policy
                // for less-trusted content.
                val shownOrigin = origin ?: around
                val inheritedLinks = LocalUriHandler.current
                val links = remember(inheritedLinks, shownOrigin, logger) { uriHandlerFor(shownOrigin, inheritedLinks, logger) }
                CompositionLocalProvider(
                    LocalLoadableSources provides inside,
                    LocalJSONContentOrigin provides shownOrigin,
                    LocalUriHandler provides links,
                ) {
                    ProvideTextStyleEnvironment(loaded.properties, logger) {
                        builder.BuildViewWithModifiers(loaded, modifier)
                    }
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

    /**
     * Merges a successfully loaded sub-tree into [windowModel] (no-op otherwise) and returns
     * the outcome to show: [outcome], or a failure when the window refuses the content
     * (less-trusted content using a trusted element's id). A LoadableView with an id owns
     * what its content merged, so a reload replaces it.
     */
    private fun mergeIntoWindow(outcome: DescriptionLoad, windowModel: WindowModel?, ownerID: Int, origin: JSONContentOrigin?): DescriptionLoad {
        if (outcome !is DescriptionLoad.Loaded) return outcome
        return try {
            windowModel?.loadSubDescription(outcome.element, parentID = if (ownerID > 0) ownerID else 0, origin = origin)
            outcome
        } catch (e: WindowModel.SubViewRefusedException) {
            DescriptionLoad.Failed(e.message ?: "id conflict")
        }
    }

    @Composable
    private fun ErrorText(message: String, modifier: Modifier) {
        M3Text(message, color = MaterialTheme.colorScheme.error, modifier = modifier.padding(16.dp))
    }
}

/**
 * The sources of the LoadableViews around a composable, as the nesting rule knows them
 * ([loadableNestingKey]), the outermost first. Empty outside any LoadableView.
 */
internal val LocalLoadableSources = staticCompositionLocalOf<List<String>> { emptyList() }
