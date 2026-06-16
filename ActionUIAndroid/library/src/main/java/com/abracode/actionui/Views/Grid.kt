package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.parseAlignment
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.numberProperty
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Static two-dimensional table of cells with aligned columns. Mirror of the
 * Apple `Grid` element (`ActionUI/Views/Grid.swift`), which wraps
 * `SwiftUI.Grid`/`GridRow`. The cells come from the element's `rows` named
 * container (an array of arrays; see [ActionUIElement.rows]); each inner array
 * is one row, in column order, and rows may be ragged (shorter rows simply
 * have fewer cells, as on Apple).
 *
 * **Rendering.** Compose has no static column-aligning grid (`LazyVerticalGrid`
 * is a scrolling viewport with uniform tracks, the wrong shape), so this is a
 * small custom [Layout] - the "custom dependency-free UI when nothing native
 * fits" case: every cell is measured at its natural size, each column is as
 * wide as its widest cell and each row as tall as its tallest (the defining
 * SwiftUI `Grid` behavior), and cells are aligned within their cell box.
 *
 * **Supported properties** (all optional, Apple's contract):
 *   * `alignment` - position of each cell within its cell box, the nine
 *     SwiftUI names resolved by [parseAlignment]; defaults to `center`.
 *   * `horizontalSpacing` / `verticalSpacing` - gaps between columns / rows;
 *     default 0, the same "absent spacing adds nothing" stance as the stacks
 *     (SwiftUI's nil means "platform default spacing").
 *
 * **Runtime row insertion** is supported: `rows` is declared in
 * [insertableContainers] as a [ContainerShape.ROWS] container, so a host adds a
 * row of cells with `ActionUIModel.insertRow` and the grid recomposes (the
 * `effectiveElement` merge feeds the new `rows` straight into the layout).
 *
 * **Not ported with the element:** the per-cell modifiers SwiftUI offers outside
 * the JSON contract (`gridCellColumns` span and friends) do not exist on Apple's
 * ActionUI either.
 *
 * Sample JSON:
 * ```
 * { "type": "Grid",
 *   "properties": { "alignment": "leading", "horizontalSpacing": 16.0 },
 *   "rows": [
 *     [ { "type": "Text", ... }, { "type": "Text", ... } ],
 *     [ { "type": "Image", ... } ]
 *   ] }
 * ```
 */
object Grid : ActionUIViewConstruction {

    override val insertableContainers = mapOf("rows" to ContainerShape.ROWS)
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val config = resolveGridConfig(element.properties, logger)
        val rows = element.rows.orEmpty().map { row ->
            row.filter { ActionUIRegistry.lookup(it.type) != null }
        }.filter { it.isNotEmpty() }
        val alignment = parseAlignment(config.alignment ?: "") ?: Alignment.Center

        Layout(
            content = {
                rows.forEach { row ->
                    row.forEach { cell ->
                        // Lookup cannot fail: the rows were pre-filtered above, which
                        // keeps the measurable count in sync with the row structure.
                        val builder = ActionUIRegistry.lookup(cell.type) ?: return@forEach
                        ProvideTextStyleEnvironment(cell.properties, logger) {
                            // No scoped buildChildModifier here: a custom Layout has no
                            // Row/Column/Box scope, and cell positioning is the grid
                            // alignment's job (the LazyVGrid precedent).
                            builder.BuildViewWithModifiers(cell, Modifier)
                        }
                    }
                }
            },
            modifier = modifier,
        ) { measurables, constraints ->
            // Each cell measured at its natural size within the incoming
            // bounds; the columns are then sized to the widest cell.
            val loose = constraints.copy(minWidth = 0, minHeight = 0)
            val placeables = measurables.map { it.measure(loose) }

            // Regroup the flat measurable list back into the row structure.
            val rowSizes = rows.map { it.size }
            var next = 0
            val placeableRows = rowSizes.map { count ->
                placeables.subList(next, next + count).also { next += count }
            }

            val cellSizes = placeableRows.map { row -> row.map { IntSize(it.width, it.height) } }
            val hGap = config.horizontalSpacing.dp.roundToPx()
            val vGap = config.verticalSpacing.dp.roundToPx()
            val metrics = computeGridMetrics(cellSizes, hGap, vGap)

            layout(
                metrics.width.coerceIn(constraints.minWidth, constraints.maxWidth),
                metrics.height.coerceIn(constraints.minHeight, constraints.maxHeight),
            ) {
                var y = 0
                placeableRows.forEachIndexed { r, row ->
                    var x = 0
                    row.forEachIndexed { c, placeable ->
                        val cellBox = IntSize(metrics.columnWidths[c], metrics.rowHeights[r])
                        val offset = alignment.align(
                            IntSize(placeable.width, placeable.height), cellBox, layoutDirection,
                        )
                        placeable.placeRelative(x + offset.x, y + offset.y)
                        x += cellBox.width + hGap
                    }
                    y += metrics.rowHeights[r] + vGap
                }
            }
        }
    }
}

/** Resolved, validated grid properties. */
internal data class GridConfig(
    val alignment: String? = null,
    val horizontalSpacing: Double = 0.0,
    val verticalSpacing: Double = 0.0,
)

/**
 * Resolves and validates `alignment` / `horizontalSpacing` / `verticalSpacing`,
 * mirroring the Apple `Grid.validateProperties` warnings (an unknown alignment
 * or a non-numeric spacing warns and is ignored). Pure (logging aside) so it
 * is unit-testable.
 */
internal fun resolveGridConfig(props: JsonObject?, logger: ActionUILogger?): GridConfig {
    if (props == null) return GridConfig()

    var alignment: String? = null
    if (props["alignment"] != null) {
        val name = (props["alignment"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        if (name != null && parseAlignment(name) != null) {
            alignment = name
        } else {
            logger?.log(
                "Grid alignment '${name ?: props["alignment"]}' invalid; defaulting to nil",
                LoggerLevel.warning,
            )
        }
    }

    fun spacing(key: String): Double {
        if (props[key] == null) return 0.0
        val number = props.numberProperty(key)
        if (number == null) {
            logger?.log("Grid $key must be a number; ignoring", LoggerLevel.warning)
            return 0.0
        }
        return number
    }

    return GridConfig(alignment, spacing("horizontalSpacing"), spacing("verticalSpacing"))
}

/** Column widths, row heights, and the total span of a measured grid. */
internal data class GridMetrics(
    val columnWidths: List<Int>,
    val rowHeights: List<Int>,
    val width: Int,
    val height: Int,
)

/**
 * The table layout math: each column is as wide as its widest cell across all
 * rows (ragged rows contribute only to the columns they reach), each row as
 * tall as its tallest cell, and the gaps go between tracks only. Pure so it is
 * unit-testable without a Compose host.
 */
internal fun computeGridMetrics(
    cellSizes: List<List<IntSize>>,
    horizontalGap: Int,
    verticalGap: Int,
): GridMetrics {
    val columnCount = cellSizes.maxOfOrNull { it.size } ?: 0
    val columnWidths = List(columnCount) { c ->
        cellSizes.maxOf { row -> row.getOrNull(c)?.width ?: 0 }
    }
    val rowHeights = cellSizes.map { row -> row.maxOfOrNull { it.height } ?: 0 }
    val width = columnWidths.sum() + horizontalGap * (columnWidths.size - 1).coerceAtLeast(0)
    val height = rowHeights.sum() + verticalGap * (rowHeights.size - 1).coerceAtLeast(0)
    return GridMetrics(columnWidths, rowHeights, width, height)
}
