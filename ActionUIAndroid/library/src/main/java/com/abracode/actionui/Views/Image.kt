package com.abracode.actionui.Views

import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ImageSource
import com.abracode.actionui.Helpers.MaterialNameIcon
import com.abracode.actionui.Helpers.SystemSymbolIcon
import com.abracode.actionui.Helpers.loadImagePainter
import com.abracode.actionui.Helpers.resolveContentScale
import com.abracode.actionui.Helpers.selectImageSource
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a bundled raster image, a filesystem image, or a Material Symbol icon.
 *
 * Mirror of the Apple `Image` element (`ActionUI/Views/Image.swift`). Source
 * selection, scaling, and axis resolution live in the shared `ImageResolver` seam
 * (`Helpers/ImageResolver.kt`); the glyph draw lives in the shared `SymbolIcon`
 * seam (`Helpers/SymbolIcon.kt`), which `Label` and Button image-labels reuse.
 * This builder stays thin and routes to the right renderer.
 *
 * **Supported sources.**
 *   * `resourceName`        -> a file in `assets/` (e.g. `"logo.png"`), raster.
 *   * `filePath`            -> an absolute filesystem path to a raster image.
 *   * `materialName:android` -> a Material Symbol, rendered as a variable-font
 *     glyph the way `Image(systemName:)` renders an SF Symbol. The icon is
 *     treated as an *image*: tinted by the inherited `foregroundStyle`, sized
 *     from `imageScale` + the ambient font (no platform divergence needed),
 *     with optional `:android` axis overrides.
 *   * `systemName`          -> an SF Symbol, mapped to the closest Material glyph
 *     via the bundled SF->Material map and rendered through the same glyph path.
 *     Per-symbol fill/weight tuning rides in the map, so shared cross-platform
 *     JSON renders right with no `:android` keys; an explicit `:android` axis knob
 *     still overrides the map.
 *
 * **Deferred vs. Apple** (warn-and-skip, not silent):
 *   * `assetName`  -> Android `res/drawable`; pending a name->resource contract.
 *
 * **Scaling.** For raster sources, `contentMode` (`fit`/`fill`) maps to a Compose
 * `ContentScale` via [resolveContentScale]. For symbols, `imageScale`
 * (`small`/`medium`/`large`) scales the glyph relative to the ambient font; the
 * `materialSize:android` override sets an explicit size in sp.
 *
 * **Axis overrides (Material symbols, `:android`).** `materialWeight` (100..700),
 * `materialFill` (0..1 or boolean), `materialGrade` (-50..200). Defaults reproduce
 * a regular, unfilled icon; per-symbol tuning is intended to live in the
 * SF->Material map so shared JSON needs no overrides.
 *
 * **Accessibility.** `accessibilityLabel` -> `contentDescription`.
 *
 * **Known limitation.** A frame (`width`/`height`) does not scale a glyph (it is
 * text, not a resizable painter); use `imageScale` or `materialSize:android`.
 *
 * Sample JSON:
 * ```
 * { "type": "Image", "properties": { "materialName:android": "favorite",
 *   "materialFill:android": 1, "imageScale": "large", "foregroundStyle": "red" } }
 * ```
 */
object Image : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val context = LocalContext.current

        // Source selection (+ its warnings) runs once per properties change.
        val source = remember(props) { selectImageSource(props, logger) }
        val imageScale = props?.stringProperty("imageScale")
        val contentDescription = props?.stringProperty("accessibilityLabel")

        when (source) {
            null -> return

            is ImageSource.MaterialSymbol -> {
                // materialName -> codepoint + glyph via the shared SymbolIcon seam;
                // axes were already resolved + clamped in selectImageSource.
                val rendered = MaterialNameIcon(
                    name = source.name,
                    weight = source.weight,
                    fill = source.fill,
                    grade = source.grade,
                    explicitSizeSp = source.explicitSizeSp,
                    imageScale = imageScale,
                    contentDescription = contentDescription,
                    modifier = modifier,
                    logger = logger,
                )
                if (!rendered) {
                    // Unknown name -> render nothing, warned once per source.
                    remember(source) {
                        logger?.log(
                            "Image materialName '${source.name}' is not a known Material " +
                                "Symbol in the bundled font. Nothing rendered.",
                            LoggerLevel.warning
                        )
                    }
                }
            }

            is ImageSource.SystemSymbol -> {
                // systemName -> SF->Material map -> glyph via the shared SymbolIcon
                // seam. Explicit :android knobs override the map's per-row tuning.
                val rendered = SystemSymbolIcon(
                    name = source.name,
                    explicitWeight = source.explicitWeight,
                    explicitFill = source.explicitFill,
                    explicitGrade = source.explicitGrade,
                    explicitSizeSp = source.explicitSizeSp,
                    imageScale = imageScale,
                    contentDescription = contentDescription,
                    modifier = modifier,
                    logger = logger,
                )
                if (!rendered) {
                    remember(source) {
                        logger?.log(
                            "Image systemName '${source.name}' has no SF->Material mapping " +
                                "(or the map asset is absent). Nothing rendered; add " +
                                "'materialName:android' for an explicit Android glyph.",
                            LoggerLevel.warning
                        )
                    }
                }
            }

            else -> {
                // Raster sources (Asset / FilePath): decode once per source.
                val painter = remember(source, context) {
                    loadImagePainter(source, context, logger)
                }
                // Unresolvable -> render nothing (the warning was already logged).
                // Diverges from Apple's SF-Symbol "photo" placeholder; Android has
                // no built-in equivalent drawable.
                if (painter == null) return

                FoundationImage(
                    painter = painter,
                    contentDescription = contentDescription,
                    modifier = modifier,
                    contentScale = resolveContentScale(props, logger),
                )
            }
        }
    }
}
