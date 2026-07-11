package com.abracode.actionui.addon.cachedimage

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.asyncimagecache.CachedImage
import com.abracode.asyncimagecache.ContentMode
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.floatOrNull

/**
 * The ActionUI `CachedImage` add-on element for Android: a cached, off-main image view backed by the
 * AsyncImageCache library's two-tier (memory + on-disk) [com.abracode.asyncimagecache.ImageStore]. A 1:1
 * mirror of the Apple add-on `Add-ons/ActionUICachedImage` (`CachedImage.swift`), which wraps the very same
 * `AsyncImageCache.CachedImage` view - so a document authored for Apple renders equivalently here.
 *
 * Linking this module is all a client does: [CachedImageProvider] registers the element at app startup
 * (the Android analog of Apple's `ActionUICachedImage.register()` launch call).
 *
 * Sample JSON (Apple's contract, key for key):
 * ```
 * {
 *   "type": "CachedImage",
 *   "id": 1,                                            // Optional: positive id for the value bridge
 *   "properties": {
 *     "url": "https://example.com/photo.jpg",          // Optional: web/file/data URL; seeds the value
 *     "intrinsicSize": { "width": 1024, "height": 768 },// Optional: natural size for zero-reflow layout
 *     "contentMode": "fill",                            // Optional: "fit"|"fill"; default "fill"
 *     "maxPixelWidth": 840,                             // Optional: cap decoded width in PIXELS (off-main)
 *     "cornerRadius": 12,                               // Optional: rounds the IMAGE (CachedImage's own clip)
 *     "frame": { "maxWidth": "infinity" }               // Baseline sizing
 *   }
 * }
 * ```
 *
 * **Value bridge** ([ActionUIValueType.STRING], Apple's contract): the runtime value is the image URL
 * string. A host `setElementValue(..)` write overrides the static `url` and re-points the image; the load
 * restarts because the wrapped view keys its work on the resolved URL. Like the core `AsyncImage` element,
 * the `url` property seeds [initialValue].
 *
 * **cornerRadius rounds the image, not the frame.** The Apple element consumes `cornerRadius` and hands it
 * to `CachedImage`'s own continuous clip (which sits right around the aspect-fit image). Here it is passed to
 * the composable's `cornerRadius` parameter, whose `Modifier.clip` is applied AFTER the aspect-ratio box, so
 * it rounds the image itself. ActionUI's baseline `cornerRadius` modifier (applied by ModifierResolver to the
 * incoming [modifier]) also clips with the SAME radius; because both clips use the identical radius the
 * rounding is idempotent (same region, no artifact), so the net result matches Apple's rounded image. This is
 * a mechanism divergence from Apple - which removes `cornerRadius` from the baseline dict so only its own clip
 * runs - but the observable result is the same.
 */
object CachedImageView : ActionUIViewConstruction {

    // The element's runtime value is the image URL string (like the core AsyncImage element).
    override val valueType = ActionUIValueType.STRING

    // Seed the value from the `url` property. Unlike Apple (whose external add-on cannot read the validated
    // properties from initialValue, so it seeds "" and resolves url in buildView), the Android element reads
    // element.properties directly here, matching the core AsyncImage element.
    override fun initialValue(element: ActionUIElement): Any? =
        (element.properties?.get("url") as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** Registers this object as the `CachedImage` element. Called by [CachedImageProvider] at startup. */
    fun register() {
        ActionUIRegistry.register("CachedImage", this)
    }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val config = remember(element.properties) { resolveCachedImageConfig(element.properties, logger) }

        // The runtime value (a host write) overrides the static `url`, Apple parity.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val urlString = (viewModel?.value as? String)?.takeIf { it.isNotEmpty() } ?: config.url

        CachedImage(
            url = urlString?.takeIf { it.isNotEmpty() },
            modifier = modifier,
            intrinsicSize = config.intrinsicSize,
            cornerRadius = config.cornerRadius.dp,
            contentMode = if (config.contentModeFill) ContentMode.Fill else ContentMode.Fit,
            maxPixelWidth = config.maxPixelWidth,
        )
    }
}

/** The element's validated properties, resolved once per `properties` change (internal for JVM unit tests). */
internal data class CachedImageConfig(
    val url: String? = null,
    val intrinsicSize: Size? = null,
    val contentModeFill: Boolean = true,   // default "fill" (CachedImage's own default)
    val maxPixelWidth: Float? = null,
    val cornerRadius: Float = 0f,          // dp; rounds the image
)

/**
 * Validates the CachedImage properties, warn-and-skip with Apple's messages
 * (`ActionUICachedImage/Sources/CachedImage.swift` `validateProperties`). Any *string* `url` is accepted -
 * even an unloadable one - because load failure is a runtime state, not a validation error, matching Apple.
 */
internal fun resolveCachedImageConfig(props: JsonObject?, logger: ActionUILogger?): CachedImageConfig {
    if (props == null) return CachedImageConfig()

    val url = props.stringOrNull("url", logger)

    val contentModeFill = when (val mode = props.stringOrNull("contentMode", logger)) {
        null, "fill" -> true
        "fit" -> false
        else -> {
            logger?.log("CachedImage contentMode '$mode' invalid (expected fit|fill); ignoring", LoggerLevel.warning)
            true
        }
    }

    val maxPixelWidth = props.numberOrNull("maxPixelWidth", logger)
    val cornerRadius = props.numberOrNull("cornerRadius", logger) ?: 0f
    val intrinsicSize = intrinsicSizeOf(props["intrinsicSize"], logger)

    return CachedImageConfig(
        url = url,
        intrinsicSize = intrinsicSize,
        contentModeFill = contentModeFill,
        maxPixelWidth = maxPixelWidth,
        cornerRadius = cornerRadius,
    )
}

// --- JSON coercion. The library's stringProperty/numberProperty helpers are `internal`, so an external
// add-on module reads the kotlinx JsonObject directly, like the map modules do. ---

/** A JSON string value, or null (with a warning) if present but not a string. */
private fun JsonObject.stringOrNull(key: String, logger: ActionUILogger?): String? {
    val primitive = this[key] as? JsonPrimitive ?: return null
    if (!primitive.isString) {
        logger?.log("Invalid type for CachedImage $key: expected String, ignoring", LoggerLevel.warning)
        return null
    }
    return primitive.content
}

/** A JSON numeric value as Float, or null (with a warning) if present but not a number. Rejects booleans. */
private fun JsonObject.numberOrNull(key: String, logger: ActionUILogger?): Float? {
    val primitive = this[key] as? JsonPrimitive ?: return null
    if (primitive.isString) {
        logger?.log("Invalid type for CachedImage $key: expected Number, ignoring", LoggerLevel.warning)
        return null
    }
    val value = primitive.floatOrNull
    if (value == null) {
        logger?.log("Invalid type for CachedImage $key: expected Number, ignoring", LoggerLevel.warning)
    }
    return value
}

/**
 * Parses an `{ "width": Number, "height": Number }` object into a [Size]; null (with a warning) if the shape
 * or either component is missing or non-numeric. Zero / negative dimensions are rejected - an intrinsic size
 * must be positive to reserve a box (CachedImage divides by it to derive an aspect ratio). Mirrors Apple's
 * `intrinsicSize(from:)`.
 */
private fun intrinsicSizeOf(raw: Any?, logger: ActionUILogger?): Size? {
    if (raw == null) return null
    val obj = raw as? JsonObject
    val width = obj?.numberOrNull("width", null)
    val height = obj?.numberOrNull("height", null)
    if (obj == null || width == null || height == null || width <= 0f || height <= 0f) {
        logger?.log(
            "CachedImage intrinsicSize must be an object with positive numeric width and height; ignoring",
            LoggerLevel.warning,
        )
        return null
    }
    return Size(width, height)
}
