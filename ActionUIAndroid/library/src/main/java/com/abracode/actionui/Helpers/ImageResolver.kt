package com.abracode.actionui.Helpers

import android.content.Context
import android.graphics.BitmapFactory
import androidx.annotation.DrawableRes
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import com.abracode.actionui.Common.ActionUIImageRegistry
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.AUI_DRAWABLE_PREFIX
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.normalizeAssetDrawableName
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.io.File
import java.io.IOException

/**
 * Shared image-resolution seam for ActionUI Android. The single place that turns
 * an element's image-source properties into a Compose [Painter], so `Image`
 * (and, later, `Label` / `Button` image labels) converge on one contract -
 * mirroring how the Apple side resolves images centrally.
 *
 * ## Apple image sources vs. Android
 *
 * The shared JSON can carry several kinds of image source (names mirror
 * `ActionUI/Views/Image.swift`, plus the Android-only `materialName`). The
 * unsupported kinds are deferred with an honest warn-and-skip rather than a
 * silent no-op:
 *
 * | Property            | Means                  | Android mapping                          | Status   |
 * |---------------------|------------------------|------------------------------------------|----------|
 * | `filePath`          | filesystem path        | [File] -> decode -> [BitmapPainter]      | **done** |
 * | `resourceName`      | bundle file (name+ext) | `assets/<name>` via [Context.getAssets]  | **done** |
 * | `materialName`      | Material Symbol name   | variable-font glyph ([MaterialSymbolGlyph]) | **done** |
 * | `systemName`        | SF Symbol              | SF->Material map -> glyph ([systemSymbol]) | **done** |
 * | `assetName`         | asset-catalog image    | `res/drawable/` via the host registry    | **done** |
 *
 * `materialName` is Android-only; authors write it as `materialName:android` and
 * `PlatformFilter` normalizes it to `materialName` here. Both `materialName` and
 * `systemName` render a Material glyph: a cross-platform JSON can carry `systemName`
 * (Apple) alongside `materialName:android` (Android), and the explicit Android
 * source wins on Android (see priority below). `systemName` resolves through the
 * bundled SF->Material map ([systemSymbol]); when a row carries fill/weight tuning
 * the author gets the right look for free, still overridable by an explicit
 * `:android` axis knob.
 *
 * `assetName` (Android `res/drawable`) resolves through the host-supplied
 * [ActionUIImageRegistry] (`Common/ImageRegistry.kt`): an explicit name ->
 * `R.drawable` map, the `aui_*` discovery convention, or both. No registry, or a
 * name the registry does not know, warns and renders nothing (mirroring Apple,
 * where a name absent from the catalog renders nothing) - it does NOT fall
 * through to a lower-priority source, so integration gaps surface instead of
 * hiding. See `Private/Android_Asset_Image_Design.md`.
 *
 * ## Source priority
 *
 * When several source properties are present, the highest-priority one wins:
 * `filePath` > `resourceName` > `materialName` > `assetName` > `systemName`.
 * That is Apple's order (`filePath` > `resourceName` > `assetName` >
 * `systemName`, `Image.swift`) with the Android-only `materialName` inserted
 * ahead of the shared keys it exists to override.
 *
 * ## Scaling
 *
 * [resolveContentScale] maps Apple's `contentMode` (`fit`/`fill`) to a Compose
 * [ContentScale] for raster sources. `imageScale` sizes symbol glyphs (Material and
 * SF) via [resolveSymbolSizeSp] in the `Image` builder.
 *
 * Unresolvable or invalid input is warned through the optional [ActionUILogger]
 * and skipped, consistent with the resolver's "unknown value -> warn + skip"
 * contract elsewhere.
 */

/** A concrete, supported image source ready to be rendered. */
internal sealed interface ImageSource {
    /** A bundle resource loaded from the app's `assets/` directory (e.g. `"logo.png"`). */
    data class Asset(val name: String) : ImageSource

    /** A raster/PDF-less image at an absolute filesystem path. */
    data class FilePath(val path: String) : ImageSource

    /**
     * A `res/drawable` resource, resolved from an asset-catalog name
     * (`assetName` / `assetImage` / `imageName`) by the host's
     * [ActionUIImageRegistry]. Rendered with `painterResource` (a composable
     * call, so not via [loadImagePainter]), which applies density buckets,
     * `-night` variants, and vector inflation - the asset-catalog feature set.
     */
    data class DrawableResource(@DrawableRes val resId: Int) : ImageSource

    /**
     * A Material Symbol icon, rendered as a variable-font glyph rather than a
     * [Painter] (see [MaterialSymbolGlyph]). [name] is a Material Symbol name
     * (resolved to a codepoint by [materialCodepoint]); the axis values are
     * pre-resolved and clamped here. [explicitSizeSp] is the `materialSize`
     * override in sp, or `null` to size automatically from `imageScale` + the
     * inherited font size (see [resolveSymbolSizeSp]).
     */
    data class MaterialSymbol(
        val name: String,
        val weight: Int,
        val fill: Float,
        val grade: Int,
        val explicitSizeSp: Float?,
    ) : ImageSource

    /**
     * An SF Symbol, resolved on Android to a Material glyph via the bundled
     * SF->Material map ([systemSymbol]) - the Android analog of `Image(systemName:)`.
     * The codepoint and any per-symbol fill/weight tuning come from the map at
     * render time (it needs the [android.content.res.AssetManager]); the values
     * here are the optional explicit `:android` axis *overrides* (each `null` when
     * absent), which win over the map's per-row tuning. [explicitSizeSp] is the
     * `materialSize` override in sp, else automatic sizing (see [resolveSymbolSizeSp]).
     */
    data class SystemSymbol(
        val name: String,
        val explicitWeight: Int?,
        val explicitFill: Float?,
        val explicitGrade: Int?,
        val explicitSizeSp: Float?,
    ) : ImageSource
}

/**
 * Picks the image source to render from [properties], honoring the priority
 * `filePath` > `resourceName` > `materialName` > `assetName` > `systemName` and
 * warning on the missing / mistyped / unresolvable cases. Pure (no Android
 * framework / no asset access - the optional [registry] is an injected lookup)
 * so it is unit-testable; the codepoint + per-row tuning for a `systemName`
 * come from [systemSymbol] in the `Image` builder, and raster decoding from
 * [loadImagePainter].
 *
 * @return the chosen [ImageSource], or `null` when nothing renderable is
 *   present (a warning is emitted in that case).
 */
internal fun selectImageSource(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
    registry: ActionUIImageRegistry? = null,
): ImageSource? {
    if (properties == null) {
        warnNoSource(logger)
        return null
    }

    // Validate-and-read each source in priority order. A present-but-non-String
    // value is warned and treated as absent (mirrors Apple's per-field check).
    val filePath = properties.stringSource("filePath", logger)
    val resourceName = properties.stringSource("resourceName", logger)
    val materialName = properties.stringSource("materialName", logger)
    val assetName = properties.stringSource("assetName", logger)
    val systemName = properties.stringSource("systemName", logger)

    return when {
        filePath != null     -> ImageSource.FilePath(filePath)
        resourceName != null -> ImageSource.Asset(resourceName)
        materialName != null -> ImageSource.MaterialSymbol(
            name = materialName,
            weight = (properties.intProperty("materialWeight") ?: MATERIAL_WEIGHT_DEFAULT)
                .coerceIn(MATERIAL_WEIGHT_MIN, MATERIAL_WEIGHT_MAX),
            fill = (properties.materialFillValue() ?: MATERIAL_FILL_DEFAULT)
                .coerceIn(MATERIAL_FILL_MIN, MATERIAL_FILL_MAX),
            grade = (properties.intProperty("materialGrade") ?: MATERIAL_GRADE_DEFAULT)
                .coerceIn(MATERIAL_GRADE_MIN, MATERIAL_GRADE_MAX),
            explicitSizeSp = properties.numberProperty("materialSize")?.toFloat(),
        )
        assetName != null    ->
            resolveAssetDrawable(assetName, registry, "Image", "assetName", logger)
        systemName != null   -> ImageSource.SystemSymbol(
            // Codepoint + per-row fill/weight are resolved from the SF->Material map
            // at render time; these are the optional explicit overrides (or null).
            name = systemName,
            explicitWeight = properties.intProperty("materialWeight"),
            explicitFill = properties.materialFillValue(),
            explicitGrade = properties.intProperty("materialGrade"),
            explicitSizeSp = properties.numberProperty("materialSize")?.toFloat(),
        )
        else                 -> {
            warnNoSource(logger)
            null
        }
    }
}

/**
 * Picks the icon an image-label element (`Label` / `Button`) should draw from its
 * [properties], or `null` when it carries no icon (title-only - not an error,
 * unlike [selectImageSource]). Reuses the glyph [ImageSource] kinds so the render
 * path is shared with `Image` (`SymbolIcon.kt`).
 *
 * Mirrors Image's `materialName` > `systemName` priority, but reads the SF name
 * from `systemImage` - the Apple `Label`/`Button` spelling of `systemName`. The
 * asset-catalog source (`imageName` on Label, `assetImage` on Button, named via
 * [assetCatalogKey]) resolves through the host [registry] like Image's
 * `assetName`, and ranks *below* `systemImage` - Apple's Label order
 * (`Label.swift` tries `systemImage` first), the reverse of Image's. Pure (no
 * Android framework - [registry] is an injected lookup) so it is unit-testable;
 * the codepoint + per-row tuning come from the render seam at draw time.
 */
internal fun selectLabelIcon(
    properties: JsonObject?,
    assetCatalogKey: String,
    elementName: String,
    logger: ActionUILogger? = null,
    registry: ActionUIImageRegistry? = null,
): ImageSource? {
    if (properties == null) return null
    val materialName = properties.stringSource("materialName", logger)
    val systemImage = properties.stringSource("systemImage", logger)
    val assetImage = properties.stringSource(assetCatalogKey, logger)
    return when {
        materialName != null -> ImageSource.MaterialSymbol(
            name = materialName,
            weight = (properties.intProperty("materialWeight") ?: MATERIAL_WEIGHT_DEFAULT)
                .coerceIn(MATERIAL_WEIGHT_MIN, MATERIAL_WEIGHT_MAX),
            fill = (properties.materialFillValue() ?: MATERIAL_FILL_DEFAULT)
                .coerceIn(MATERIAL_FILL_MIN, MATERIAL_FILL_MAX),
            grade = (properties.intProperty("materialGrade") ?: MATERIAL_GRADE_DEFAULT)
                .coerceIn(MATERIAL_GRADE_MIN, MATERIAL_GRADE_MAX),
            explicitSizeSp = properties.numberProperty("materialSize")?.toFloat(),
        )
        systemImage != null -> ImageSource.SystemSymbol(
            name = systemImage,
            explicitWeight = properties.intProperty("materialWeight"),
            explicitFill = properties.materialFillValue(),
            explicitGrade = properties.intProperty("materialGrade"),
            explicitSizeSp = properties.numberProperty("materialSize")?.toFloat(),
        )
        assetImage != null ->
            resolveAssetDrawable(assetImage, registry, elementName, assetCatalogKey, logger)
        else -> null
    }
}

/**
 * Resolves an asset-catalog [name] through the host [registry], warning (and
 * returning `null` - nothing rendered, no fall-through, like a name absent
 * from Apple's catalog) when there is no registry or the name is unknown to it.
 */
private fun resolveAssetDrawable(
    name: String,
    registry: ActionUIImageRegistry?,
    elementName: String,
    sourceKey: String,
    logger: ActionUILogger?,
): ImageSource.DrawableResource? {
    val resId = registry?.drawableFor(name)
    if (resId != null) return ImageSource.DrawableResource(resId)
    val cause = if (registry == null) {
        "no image registry was supplied (ActionUI.Render(images = ...) or ActionUI.defaultImageRegistry)"
    } else {
        "the host image registry does not resolve it"
    }
    logger?.log(
        "$elementName $sourceKey '$name': $cause. Map it with imageRegistryOf(...), " +
            "name a drawable '${AUI_DRAWABLE_PREFIX}${normalizeAssetDrawableName(name)}' for " +
            "DiscoveringImageRegistry, or use a '$sourceKey:android' override. Nothing rendered.",
        LoggerLevel.warning
    )
    return null
}

/**
 * Reads the `materialFill` axis, which accepts either a number in 0..1 or a
 * boolean (`true` -> 1, `false` -> 0; SF's `.fill` variant is the binary case).
 * Returns `null` if absent or an unusable type.
 */
private fun JsonObject.materialFillValue(): Float? {
    val primitive = this["materialFill"] as? JsonPrimitive ?: return null
    primitive.booleanOrNull?.let { return if (it) 1f else 0f }
    primitive.doubleOrNull?.let { return it.toFloat() }
    return null
}

/**
 * Finalizes a symbol's axis values for a `systemName`, applying the precedence
 * **explicit `:android` override > per-row map tuning > hard default**, then
 * clamping to the font's range. Pure / unit-testable. (`materialName` axes are
 * resolved inline in [selectImageSource] since it has no per-row map tuning.)
 */
internal fun resolveSymbolWeight(explicit: Int?, mapWeight: Int?): Int =
    (explicit ?: mapWeight ?: MATERIAL_WEIGHT_DEFAULT)
        .coerceIn(MATERIAL_WEIGHT_MIN, MATERIAL_WEIGHT_MAX)

internal fun resolveSymbolFill(explicit: Float?, mapFill: Boolean): Float =
    (explicit ?: if (mapFill) 1f else MATERIAL_FILL_DEFAULT)
        .coerceIn(MATERIAL_FILL_MIN, MATERIAL_FILL_MAX)

internal fun resolveSymbolGrade(explicit: Int?): Int =
    (explicit ?: MATERIAL_GRADE_DEFAULT)
        .coerceIn(MATERIAL_GRADE_MIN, MATERIAL_GRADE_MAX)

/** Default symbol size (sp) when neither `materialSize` nor an inherited font size applies. */
internal const val DEFAULT_SYMBOL_SIZE_SP = 20f

/**
 * `imageScale` multipliers and the font-to-symbol box factor, calibrated against
 * the real SF Symbol sizes (measured via `NSImage.SymbolConfiguration` at a 17pt
 * body font: medium boxes are ~20pt -> 1.18x the font size; small/large are
 * 16/26pt -> 0.80x/1.28x of medium - figures consistent across glyph shapes).
 * Material glyphs are drawn at em == size, so without [SYMBOL_FONT_BOX_FACTOR]
 * they read visibly smaller next to the same title than SF Symbols do.
 */
internal const val IMAGE_SCALE_SMALL_FACTOR = 0.8f
internal const val IMAGE_SCALE_LARGE_FACTOR = 1.28f
internal const val SYMBOL_FONT_BOX_FACTOR = 1.18f

/**
 * Resolves the rendered glyph size (sp), mirroring how an SF Symbol image is
 * sized: relative to the surrounding font, scaled by `imageScale`. Pure /
 * unit-testable.
 *
 *   1. base = [explicitSizeSp] (the `materialSize:android` override, taken
 *      as-is) if set, else [inheritedFontSizeSp] (the ambient `font` size) *
 *      [SYMBOL_FONT_BOX_FACTOR] (an SF Symbol renders larger than its font -
 *      see the factor docs), else [DEFAULT_SYMBOL_SIZE_SP].
 *   2. multiplied by the `imageScale` factor (`small`/`large`; `medium`, `null`,
 *      or an invalid value leave it unscaled).
 */
internal fun resolveSymbolSizeSp(
    explicitSizeSp: Float?,
    imageScale: String?,
    inheritedFontSizeSp: Float?,
): Float {
    val base = explicitSizeSp
        ?: inheritedFontSizeSp?.times(SYMBOL_FONT_BOX_FACTOR)
        ?: DEFAULT_SYMBOL_SIZE_SP
    val factor = when (imageScale?.lowercase()) {
        "small" -> IMAGE_SCALE_SMALL_FACTOR
        "large" -> IMAGE_SCALE_LARGE_FACTOR
        else    -> 1f
    }
    return base * factor
}

/**
 * The frame box (dp) a *resizable* glyph should scale to, or `null` when the
 * element is not resizable or carries no usable fixed `frame`. Mirrors SwiftUI,
 * where `.resizable()` makes `Image(systemName:)` scale to its frame instead of
 * drawing at the font-relative size (and `imageScale` no longer applies - the
 * caller passes the result as the explicit size with no scale).
 *
 * `resizable` follows the Apple contract: the explicit boolean wins, else it is
 * implied by a `contentMode` (see `Image.swift`). With both axes given,
 * `contentMode: "fill"` takes the larger (the square glyph em overflows the
 * short axis - the crop analog), anything else aspect-fits the smaller; a
 * single-axis frame uses that axis. Pure / unit-testable.
 */
internal fun resolveResizableGlyphFrameDp(properties: JsonObject?): Float? {
    if (properties == null) return null
    val contentMode = properties.stringProperty("contentMode")
    val resizable = properties.booleanProperty("resizable") ?: (contentMode != null)
    if (!resizable) return null
    val frame = properties["frame"] as? JsonObject ?: return null
    val width = frame.numberProperty("width")?.toFloat()
    val height = frame.numberProperty("height")?.toFloat()
    return when {
        width != null && height != null ->
            if (contentMode == "fill") maxOf(width, height) else minOf(width, height)
        else -> width ?: height
    }
}

/**
 * Maps the `contentMode` property (`fit`/`fill`) to a Compose [ContentScale].
 * Defaults to [ContentScale.Fit] when unset or invalid. Pure / unit-testable.
 *
 *   * `"fit"`  -> [ContentScale.Fit]  (aspect-fit; SwiftUI `.aspectRatio(.fit)`)
 *   * `"fill"` -> [ContentScale.Crop] (aspect-fill with overflow cropped; `.fill`)
 */
internal fun resolveContentScale(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): ContentScale {
    if (properties == null) return ContentScale.Fit

    return when (val mode = properties.stringProperty("contentMode")?.lowercase()) {
        null   -> ContentScale.Fit
        "fit"  -> ContentScale.Fit
        "fill" -> ContentScale.Crop
        else   -> {
            logger?.log(
                "Image contentMode '$mode' invalid; expected 'fit' or 'fill'. Using 'fit'.",
                LoggerLevel.warning
            )
            ContentScale.Fit
        }
    }
}

/**
 * Decodes a resolved [ImageSource] into a Compose [Painter]. Needs the Android
 * [Context] for `assets/` access, so it is **not** unit-testable without
 * Robolectric - call it from the element builder inside a `remember` so the I/O
 * and decode run once per source rather than per recomposition.
 *
 * @return a [BitmapPainter], or `null` if the asset/file is missing or fails to
 *   decode (a warning is emitted).
 */
internal fun loadImagePainter(
    source: ImageSource,
    context: Context,
    logger: ActionUILogger? = null
): Painter? = when (source) {
    is ImageSource.Asset            -> decodeAsset(source.name, context, logger)
    is ImageSource.FilePath         -> decodeFile(source.path, logger)
    // Symbol sources are glyphs, not raster painters; the Image builder renders
    // them via MaterialSymbolGlyph and never routes them here. A drawable is
    // rendered with the composable painterResource (density/night/vector aware),
    // so it never routes here either.
    is ImageSource.MaterialSymbol   -> null
    is ImageSource.SystemSymbol     -> null
    is ImageSource.DrawableResource -> null
}

private fun decodeAsset(name: String, context: Context, logger: ActionUILogger?): Painter? =
    try {
        val bitmap = context.assets.open(name).use { BitmapFactory.decodeStream(it) }
        if (bitmap == null) {
            logger?.log(
                "Image: asset '$name' could not be decoded (not a raster image?). " +
                    "Nothing rendered.",
                LoggerLevel.warning
            )
            null
        } else {
            BitmapPainter(bitmap.asImageBitmap())
        }
    } catch (e: IOException) {
        logger?.log(
            "Image: resourceName '$name' not found in assets/. Nothing rendered.",
            LoggerLevel.warning
        )
        null
    }

private fun decodeFile(path: String, logger: ActionUILogger?): Painter? {
    if (!File(path).exists()) {
        logger?.log(
            "Image: filePath '$path' does not exist. Nothing rendered.",
            LoggerLevel.warning
        )
        return null
    }
    val bitmap = BitmapFactory.decodeFile(path)
    if (bitmap == null) {
        logger?.log(
            "Image: filePath '$path' could not be decoded as an image. Nothing rendered.",
            LoggerLevel.warning
        )
        return null
    }
    return BitmapPainter(bitmap.asImageBitmap())
}

/**
 * Reads a String source property; warns and returns null if present-but-not-a-String.
 * Checks [JsonPrimitive.isString] rather than [stringProperty] because the latter
 * stringifies a JSON number (`42` -> `"42"`), which must not pass as a valid source.
 */
private fun JsonObject.stringSource(key: String, logger: ActionUILogger?): String? {
    val element = this[key] ?: return null
    val primitive = element as? JsonPrimitive
    if (primitive == null || !primitive.isString) {
        logger?.log("Image $key must be a String; ignoring.", LoggerLevel.warning)
        return null
    }
    return primitive.content
}

private fun warnNoSource(logger: ActionUILogger?) {
    logger?.log(
        "Image requires an image source: 'resourceName' (assets/), 'filePath', " +
            "'materialName:android' (Material Symbol), 'systemName' (SF Symbol, " +
            "via the bundled SF->Material map), or 'assetName' (res/drawable, " +
            "via the host image registry). Nothing rendered.",
        LoggerLevel.warning
    )
}
