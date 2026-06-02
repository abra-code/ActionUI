package com.abracode.actionui.Common

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.io.IOException

/**
 * Shared image-resolution seam for ActionUI Android. The single place that turns
 * an element's image-source properties into a Compose [Painter], so `Image`
 * (and, later, `Label` / `Button` image labels) converge on one contract —
 * mirroring how the Apple side resolves images centrally.
 *
 * ## Apple image sources vs. Android
 *
 * The shared JSON can carry four kinds of image source (names mirror
 * `ActionUI/Views/Image.swift`). Only the two "bundled raster" kinds are wired
 * up today; the other two are deferred with an honest warn-and-skip rather than
 * a silent no-op:
 *
 * | Apple property | Means                  | Android mapping                 | Status   |
 * |----------------|------------------------|---------------------------------|----------|
 * | `filePath`     | filesystem path        | [File] → decode → [BitmapPainter] | **done** |
 * | `resourceName` | bundle file (name+ext) | `assets/<name>` via [Context.getAssets] | **done** |
 * | `assetName`    | asset-catalog image    | `res/drawable/`                 | deferred |
 * | `systemName`   | SF Symbol              | Material icon / vector glyph    | deferred |
 *
 * `assetName` (Android `res/drawable`) is deferred pending a name→resource
 * contract — runtime-by-name needs `resources.getIdentifier`, which is slow and
 * stripped by R8 unless kept, so the right shape is a client-supplied map; that
 * decision is open. `systemName` (SF Symbols) has no portable name lookup on
 * Android. Both are tracked in `Private/Android_Porting_Notes.md` §10. Authors
 * who need a bundled image on Android today should use `resourceName` (drop the
 * file in `assets/`) or a platform suffix (e.g. `resourceName:android`).
 *
 * ## Source priority
 *
 * When several source properties are present, the highest-priority one wins,
 * matching the Apple mutual-exclusivity order: `filePath` > `resourceName` >
 * `assetName` > `systemName`. Because the two supported kinds outrank the two
 * deferred kinds, a cross-platform JSON that supplies both (e.g. `systemName`
 * for Apple and `resourceName` for Android) resolves correctly on Android.
 *
 * ## Scaling
 *
 * [resolveContentScale] maps Apple's `contentMode` (`fit`/`fill`) to a Compose
 * [ContentScale]. `imageScale` (Apple) only affects SF Symbols, so it is
 * ignored here until symbol support lands.
 *
 * Unresolvable or invalid input is warned through the optional [ActionUILogger]
 * and skipped, consistent with the resolver's "unknown value → warn + skip"
 * contract elsewhere.
 */

/** A concrete, supported image source ready to be decoded into a [Painter]. */
internal sealed interface ImageSource {
    /** A bundle resource loaded from the app's `assets/` directory (e.g. `"logo.png"`). */
    data class Asset(val name: String) : ImageSource

    /** A raster/PDF-less image at an absolute filesystem path. */
    data class FilePath(val path: String) : ImageSource
}

/**
 * Picks the image source to render from [properties], honoring the Apple
 * priority `filePath` > `resourceName` > `assetName` > `systemName` and warning
 * on the deferred / missing / mistyped cases. Pure (no Android framework / no
 * decoding) so it is unit-testable; [loadImagePainter] performs the actual
 * decode.
 *
 * @return the chosen [ImageSource], or `null` when nothing renderable is
 *   present (a warning is emitted in that case).
 */
internal fun selectImageSource(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): ImageSource? {
    if (properties == null) {
        warnNoSource(logger)
        return null
    }

    // Validate-and-read each source in priority order. A present-but-non-String
    // value is warned and treated as absent (mirrors Apple's per-field check).
    val filePath = properties.stringSource("filePath", logger)
    val resourceName = properties.stringSource("resourceName", logger)
    val assetName = properties.stringSource("assetName", logger)
    val systemName = properties.stringSource("systemName", logger)

    return when {
        filePath != null     -> ImageSource.FilePath(filePath)
        resourceName != null -> ImageSource.Asset(resourceName)
        assetName != null    -> {
            logger?.log(
                "Image 'assetName' ('$assetName') maps to an Android res/drawable " +
                    "resource, which is not supported yet (pending a name→resource " +
                    "contract). Use 'resourceName' (assets/) or a platform suffix " +
                    "such as 'resourceName:android'. Nothing rendered.",
                LoggerLevel.warning
            )
            null
        }
        systemName != null   -> {
            logger?.log(
                "Image 'systemName' ('$systemName') is an SF Symbol, which has no " +
                    "portable Android equivalent and is not supported yet. Use " +
                    "'resourceName'/'filePath' or a platform suffix such as " +
                    "'resourceName:android'. Nothing rendered.",
                LoggerLevel.warning
            )
            null
        }
        else                 -> {
            warnNoSource(logger)
            null
        }
    }
}

/**
 * Maps the `contentMode` property (`fit`/`fill`) to a Compose [ContentScale].
 * Defaults to [ContentScale.Fit] when unset or invalid. Pure / unit-testable.
 *
 *   * `"fit"`  → [ContentScale.Fit]  (aspect-fit; SwiftUI `.aspectRatio(.fit)`)
 *   * `"fill"` → [ContentScale.Crop] (aspect-fill with overflow cropped; `.fill`)
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
 * Robolectric — call it from the element builder inside a `remember` so the I/O
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
    is ImageSource.Asset    -> decodeAsset(source.name, context, logger)
    is ImageSource.FilePath -> decodeFile(source.path, logger)
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
 * stringifies a JSON number (`42` → `"42"`), which must not pass as a valid source.
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
        "Image requires an image source. Android supports 'resourceName' " +
            "(assets/) and 'filePath' today; 'assetName' (res/drawable) and " +
            "'systemName' (SF Symbols) are not supported yet. Nothing rendered.",
        LoggerLevel.warning
    )
}
