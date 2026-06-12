package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.parseAlignment
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Greedy container that fills all available space and reports its size. Mirror
 * of the Apple `GeometryReader` element (`ActionUI/Views/GeometryReader.swift`),
 * which wraps `SwiftUI.GeometryReader`. Its single child comes from the
 * `content` named container (see [ActionUIElement.content]).
 *
 * **Greedy, like the shapes.** SwiftUI's GeometryReader expands to fill all the
 * space its parent offers regardless of its content's size, so like `ShapeView`
 * it declares [fillMaxSize] - the element states its SwiftUI sizing nature
 * (widgets wrap, greedy elements fill), expanding through any
 * `wrapContentSize` a fixed `frame` applies. On an unbounded axis (a vertical
 * scroller's height) there is nothing to fill and the box wraps its content;
 * give it an explicit `frame` there, the usual bounded-height stance.
 *
 * **Observable contract** (Apple's, key for key): `states["size"]` holds the
 * container's current `[width, height]` as a two-element `List<Double>`,
 * seeded `[0.0, 0.0]` and updated whenever the container's measured size
 * changes. Reported in dp, the Android analog of Apple's points (the same unit
 * `frame` consumes), read via `getElementState(viewID, key = "size")`.
 *
 * **Supported properties** (Apple's contract):
 *   * `alignment` - position of the content within the reader, the nine
 *     SwiftUI names resolved by [parseAlignment]; defaults to `topLeading`,
 *     SwiftUI GeometryReader's native default (not `center` like most
 *     containers).
 *
 * Sample JSON:
 * ```
 * { "type": "GeometryReader", "id": 1,
 *   "properties": { "alignment": "center" },
 *   "content": { "type": "Text", "properties": { "text": "Content" } } }
 * ```
 */
object GeometryReader : ActionUIViewConstruction {
    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf("size" to listOf(0.0, 0.0))

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val alignmentName = resolveGeometryReaderAlignment(element.properties, logger)
        val alignment = parseAlignment(alignmentName) ?: Alignment.TopStart

        // Size reports need a positive id's ViewModel; without one the reader
        // still renders (and stays greedy), it just has nowhere to report.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val density = LocalDensity.current.density

        // The box renders even with no content, like Swift's EmptyView
        // fallback: an empty GeometryReader still occupies and reports space.
        val content = element.content
        val builder = content?.let { ActionUIRegistry.lookup(it.type) }

        Box(
            modifier = modifier
                .fillMaxSize()
                .onSizeChanged { size ->
                    val reported = geometrySizeState(size.width, size.height, density)
                    if (viewModel != null && viewModel.states["size"] != reported) {
                        viewModel.states["size"] = reported
                    }
                },
            contentAlignment = alignment,
        ) {
            if (content != null && builder != null) {
                ProvideTextStyleEnvironment(content.properties, logger) {
                    builder.BuildViewWithModifiers(content, Modifier)
                }
            }
        }
    }
}

/**
 * Resolves and validates `alignment`, mirroring the Apple
 * `GeometryReader.validateProperties` warning: an unknown name warns and falls
 * back to `topLeading`, SwiftUI GeometryReader's native default. Pure (logging
 * aside) so it is unit-testable.
 */
internal fun resolveGeometryReaderAlignment(props: JsonObject?, logger: ActionUILogger?): String {
    val raw = props?.get("alignment") ?: return "topLeading"
    val name = (raw as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
    if (name != null && parseAlignment(name) != null) return name
    logger?.log(
        "GeometryReader alignment '${name ?: raw}' invalid; defaulting to 'topLeading'",
        LoggerLevel.warning,
    )
    return "topLeading"
}

/**
 * The `states["size"]` value for a measured size: pixel dimensions converted
 * to dp doubles (`[width, height]`), the Android analog of Apple's points.
 * Pure so it is unit-testable.
 */
internal fun geometrySizeState(widthPx: Int, heightPx: Int, density: Float): List<Double> =
    listOf(widthPx / density.toDouble(), heightPx / density.toDouble())
