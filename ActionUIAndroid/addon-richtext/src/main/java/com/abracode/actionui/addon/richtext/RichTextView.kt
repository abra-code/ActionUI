package com.abracode.actionui.addon.richtext

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.richtext.rendering.RichText
import com.abracode.richtext.rendering.RichTextTheme
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.floatOrNull

/**
 * The ActionUI `RichText` add-on element for Android: a rich-text DISPLAY element that renders a whole Markdown
 * document (headings, code blocks, quotes, lists, GFM tables, inline styling, links) through the RichText
 * Compose renderer (`com.abracode.richtext`). A 1:1 mirror of the Apple add-on `Add-ons/ActionUIRichText`
 * (`RichText.swift`), which wraps the very same RichText package - so a document authored for Apple renders
 * equivalently here.
 *
 * Linking this module is all a client does: [RichTextProvider] registers the element at app startup (the
 * Android analog of Apple's `ActionUIRichText.register()` launch call).
 *
 * Sample JSON (Apple's contract, key for key):
 * ```
 * {
 *   "type": "RichText",
 *   "id": 90,                                             // Optional: positive id for the value bridge
 *   "properties": {
 *     "markdown": "# Title\n\nA **bold** word and a `code` span.",  // Optional: source; seeds the value
 *     "baseFontSize": 15,                                 // Optional: base font size; omit for the body size
 *     "syntaxHighlighting": true,                         // Optional: color fenced code by language
 *     "widthBehavior": "fill"                             // Optional: "fill" (default) | "hug"
 *   }
 * }
 * ```
 *
 * **Value bridge** ([ActionUIValueType.STRING], Apple's contract): the runtime value is the Markdown source. A
 * host `setElementValue(..)` write overrides the static `markdown` and re-renders (the parser's totality makes
 * a re-render on every write safe); the `markdown` property seeds [initialValue].
 *
 * **widthBehavior is validated but not applied.** The Apple element maps it to RichText's `.widthBehavior(...)`;
 * the Android RichText composable has no such hook (it fills the proposed width - block/document layout), so
 * "hug" is accepted-and-noted but renders as "fill". A documented add-on limitation, not a security or content
 * divergence.
 */
object RichTextView : ActionUIViewConstruction {

    // The element's runtime value is the Markdown source string (value-primary, like the Apple element).
    override val valueType = ActionUIValueType.STRING

    // Seed the value from the `markdown` property (the Android element reads element.properties directly, like
    // the CachedImage add-on and the core elements).
    override fun initialValue(element: ActionUIElement): Any? =
        (element.properties?.get("markdown") as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** Registers this object as the `RichText` element. Called by [RichTextProvider] at startup. */
    fun register() {
        ActionUIRegistry.register("RichText", this)
    }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val config = remember(element.properties) { resolveRichTextConfig(element.properties, logger) }

        // The runtime value (a host write) overrides the static `markdown`, Apple parity.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val markdown = (viewModel?.value as? String)?.takeIf { it.isNotEmpty() } ?: config.markdown

        // Start from the package default theme and override only the knobs that were provided, so untouched
        // theme values keep their defaults (matching the Apple buildView).
        var theme = RichTextTheme.Default
        config.baseFontSize?.let { theme = theme.copy(baseFontSize = it) }
        config.syntaxHighlighting?.let { theme = theme.copy(syntaxHighlighting = it) }

        // widthBehavior ("hug") has no Compose hook here; the renderer fills the proposed width. See the class doc.
        RichText(markdown = markdown, theme = theme, modifier = modifier)
    }
}

/** The element's validated properties, resolved once per `properties` change (internal for JVM unit tests). */
internal data class RichTextConfig(
    val markdown: String = "",
    val baseFontSize: Float? = null,
    val syntaxHighlighting: Boolean? = null,   // null = keep the theme default
    val widthBehaviorHug: Boolean = false,     // parsed for parity; not applied on Android (see BuildView)
)

/**
 * Validates the RichText properties, warn-and-skip with Apple's messages
 * (`ActionUIRichText/Sources/RichText.swift` `validateProperties`). A missing `markdown` yields an empty
 * document (not an error), matching Apple.
 */
internal fun resolveRichTextConfig(props: JsonObject?, logger: ActionUILogger?): RichTextConfig {
    if (props == null) return RichTextConfig()

    val markdown = props.stringOrNull("markdown", logger) ?: ""
    val baseFontSize = props.numberOrNull("baseFontSize", logger)
    val syntaxHighlighting = props.booleanOrNull("syntaxHighlighting", logger)

    val widthBehaviorHug = when (val behavior = props.stringOrNull("widthBehavior", logger)) {
        null, "fill" -> false
        "hug" -> true
        else -> {
            logger?.log("RichText widthBehavior '$behavior' invalid (expected fill|hug); ignoring", LoggerLevel.warning)
            false
        }
    }

    return RichTextConfig(
        markdown = markdown,
        baseFontSize = baseFontSize,
        syntaxHighlighting = syntaxHighlighting,
        widthBehaviorHug = widthBehaviorHug,
    )
}

// --- JSON coercion. The library's stringProperty/numberProperty/booleanProperty helpers are `internal`, so an
// external add-on module reads the kotlinx JsonObject directly, like the map / CachedImage modules do. ---

/** A JSON string value, or null (with a warning) if present but not a string. */
private fun JsonObject.stringOrNull(key: String, logger: ActionUILogger?): String? {
    val primitive = this[key] as? JsonPrimitive ?: return null
    if (!primitive.isString) {
        logger?.log("Invalid type for RichText $key: expected String, ignoring", LoggerLevel.warning)
        return null
    }
    return primitive.content
}

/** A JSON numeric value as Float, or null (with a warning) if present but not a number. Rejects strings. */
private fun JsonObject.numberOrNull(key: String, logger: ActionUILogger?): Float? {
    val primitive = this[key] as? JsonPrimitive ?: return null
    if (primitive.isString) {
        logger?.log("Invalid type for RichText $key: expected Number, ignoring", LoggerLevel.warning)
        return null
    }
    val value = primitive.floatOrNull
    if (value == null) {
        logger?.log("Invalid type for RichText $key: expected Number, ignoring", LoggerLevel.warning)
    }
    return value
}

/** A JSON boolean value, or null (with a warning) if present but not a boolean. Rejects strings. */
private fun JsonObject.booleanOrNull(key: String, logger: ActionUILogger?): Boolean? {
    val primitive = this[key] as? JsonPrimitive ?: return null
    if (primitive.isString) {
        logger?.log("Invalid type for RichText $key: expected Boolean, ignoring", LoggerLevel.warning)
        return null
    }
    val value = primitive.booleanOrNull
    if (value == null) {
        logger?.log("Invalid type for RichText $key: expected Boolean, ignoring", LoggerLevel.warning)
    }
    return value
}
