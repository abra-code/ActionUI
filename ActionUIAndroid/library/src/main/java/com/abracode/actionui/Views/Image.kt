package com.abracode.actionui.Views

import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUIImageRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ImageSource
import com.abracode.actionui.Helpers.MaterialNameIcon
import com.abracode.actionui.Helpers.SystemSymbolIcon
import com.abracode.actionui.Helpers.loadImagePainter
import com.abracode.actionui.Helpers.resolveContentScale
import com.abracode.actionui.Helpers.resolveResizableGlyphFrameDp
import com.abracode.actionui.Helpers.selectImageSource
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Renders a bundled raster image, a filesystem image, or a Material Symbol icon.
 *
 * Mirror of the Apple `Image` element (`ActionUI/Views/Image.swift`). Source
 * selection, scaling, and axis resolution live in the shared `ImageResolver` helper
 * (`Helpers/ImageResolver.kt`); the glyph draw lives in the shared `SymbolIcon`
 * helper (`Helpers/SymbolIcon.kt`), which `Label` and Button image-labels reuse.
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
 *   * `assetName`           -> an asset-catalog image, resolved to `res/drawable`
 *     by the host-supplied registry (`Common/ImageRegistry.kt`: explicit map
 *     and/or the `aui_*` discovery convention) and rendered with
 *     `painterResource` - density buckets, `-night` variants, and vector XML
 *     work like catalog scale/appearance variants. No registry or an unknown
 *     name warns-and-skips.
 *
 * **Scaling.** For raster sources, `contentMode` (`fit`/`fill`) maps to a Compose
 * `ContentScale` via [resolveContentScale]. For symbols, `imageScale`
 * (`small`/`medium`/`large`) scales the glyph relative to the ambient font; the
 * `materialSize:android` override sets an explicit size in sp. A **resizable**
 * glyph (`resizable: true`, or implied by a `contentMode` - the Apple contract)
 * instead scales to its fixed `frame`, mirroring SwiftUI's
 * `Image(systemName:).resizable().frame(...)`; `imageScale` then no longer
 * applies (see [resolveResizableGlyphFrameDp]), while `materialSize:android`
 * still wins as the explicit Android escape hatch.
 *
 * **Axis overrides (Material symbols, `:android`).** `materialWeight` (100..700),
 * `materialFill` (0..1 or boolean), `materialGrade` (-50..200). Defaults reproduce
 * a regular, unfilled icon; per-symbol tuning is intended to live in the
 * SF->Material map so shared JSON needs no overrides.
 *
 * **Accessibility.** `accessibilityLabel` (and the other universal
 * accessibility properties) arrive on [modifier] via the shared pipeline
 * (`ModifierResolver.applyCommonProperties`), which sets `contentDescription`
 * on this same node - so no per-element wiring here, and none is allowed:
 * a second `contentDescription` from the same property would be announced
 * twice (the semantics merge by list concatenation).
 *
 * **Value bridge.** Like Apple, `Image` declares [ActionUIValueType.STRING]
 * (Apple's `String?`): a host can replace the source at runtime via
 * `ActionUIModel.setElementValue(id, "...")`. A non-empty runtime value is
 * interpreted with Apple's "mixed" heuristics ([mixedImageSourceProperties]):
 * a path-like string (contains `/`) is a `filePath`, an image-extension name is
 * a `resourceName` (assets/), and a bare name is a `systemName` glyph - and it
 * overrides the static source properties. An empty / unset value falls back to
 * the authored `systemName` / `assetName` / `resourceName` / `filePath`, so
 * static usage is unchanged. `initialValue` returns only a pre-set runtime value
 * (`null` means "use the static properties"), matching Apple's `Image.swift`.
 *
 * Sample JSON:
 * ```
 * { "type": "Image", "properties": { "materialName:android": "favorite",
 *   "materialFill:android": 1, "imageScale": "large", "foregroundStyle": "red" } }
 * ```
 */
object Image : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    // Non-null only when a runtime value was explicitly set; null means "use the
    // static source properties" (the builder resolves those). Mirrors Apple's
    // `Image.initialValue`, which returns `model.value as? String`.
    override fun initialValue(element: ActionUIElement): Any? = null

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val context = LocalContext.current
        val imageRegistry = LocalActionUIImageRegistry.current

        // A non-empty runtime value (a host write) overrides the static source,
        // interpreted with Apple's "mixed" heuristics. Empty / unset -> the
        // authored properties, so static usage is unaffected.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val runtimeValue = (viewModel?.value as? String)?.takeIf { it.isNotEmpty() }
        val sourceProps = if (runtimeValue != null) mixedImageSourceProperties(runtimeValue) else props

        // Source selection (+ its warnings) runs once per effective-source change.
        val source = remember(sourceProps, imageRegistry) { selectImageSource(sourceProps, logger, imageRegistry) }
        val imageScale = props?.stringProperty("imageScale")
        // accessibilityLabel is applied as semantics on [modifier] by the
        // shared pipeline; the painter-level description stays null (see the
        // Accessibility note in the header).
        val contentDescription: String? = null

        // A resizable glyph scales to its frame instead of the font-relative
        // size (SwiftUI .resizable() semantics), and imageScale stops applying.
        // dp -> sp through the density so a user font-scale preference does not
        // change the frame fit. materialSize:android still wins if present.
        val frameFitDp = remember(props) { resolveResizableGlyphFrameDp(props) }
        val frameFitSp = frameFitDp?.let { with(LocalDensity.current) { it.dp.toSp().value } }
        val glyphScale = if (frameFitSp != null) null else imageScale

        when (source) {
            null -> return

            is ImageSource.DrawableResource -> {
                // Asset-catalog image resolved to res/drawable by the host
                // registry. painterResource supplies the catalog feature set:
                // density buckets, -night variants, vector inflation.
                FoundationImage(
                    painter = painterResource(source.resId),
                    contentDescription = contentDescription,
                    modifier = modifier,
                    contentScale = resolveContentScale(props, logger),
                )
            }

            is ImageSource.MaterialSymbol -> {
                // materialName -> codepoint + glyph via the shared SymbolIcon helper;
                // axes were already resolved + clamped in selectImageSource.
                val rendered = MaterialNameIcon(
                    name = source.name,
                    weight = source.weight,
                    fill = source.fill,
                    grade = source.grade,
                    explicitSizeSp = source.explicitSizeSp ?: frameFitSp,
                    imageScale = glyphScale,
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
                // helper. Explicit :android knobs override the map's per-row tuning.
                val rendered = SystemSymbolIcon(
                    name = source.name,
                    explicitWeight = source.explicitWeight,
                    explicitFill = source.explicitFill,
                    explicitGrade = source.explicitGrade,
                    explicitSizeSp = source.explicitSizeSp ?: frameFitSp,
                    imageScale = glyphScale,
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

/**
 * Maps a runtime value string into a single-source-key `properties` object using
 * Apple's "mixed" interpretation ([ImageHelper] `init(from:interpretation:)`,
 * `"mixed"`): a path-like string (contains `/`) becomes a `filePath`, an
 * image-extension name a `resourceName` (an `assets/` file), and a bare name a
 * `systemName` glyph (the SF->Material path, the closest portable Android analog
 * of Apple's "asset catalog name, else SF Symbol" final fallback - Android's
 * asset-catalog lookup needs the host registry and does not fall through, so a
 * bare name routes straight to the glyph path that always resolves). The result
 * is fed to the same [selectImageSource] the authored properties use, so the
 * runtime source rides one resolution path. Pure, so it is unit-testable.
 */
internal fun mixedImageSourceProperties(value: String): JsonObject = buildJsonObject {
    when {
        value.contains("/") -> put("filePath", value)
        hasImageFileExtension(value) -> put("resourceName", value)
        else -> put("systemName", value)
    }
}

/** A short list of raster image extensions, mirroring Apple's `validateImageFilePath` UTType check. */
private val IMAGE_FILE_EXTENSIONS = setOf("png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "heif", "pdf")

/** True when [name]'s extension is a known raster/PDF image extension (case-insensitive). */
private fun hasImageFileExtension(name: String): Boolean {
    val dot = name.lastIndexOf('.')
    if (dot < 0 || dot == name.length - 1) return false
    return name.substring(dot + 1).lowercase() in IMAGE_FILE_EXTENSIONS
}
