package com.abracode.actionui.Common

import android.content.Context
import androidx.annotation.DrawableRes
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Host-supplied resolution of Apple asset-catalog image names to Android
 * drawable resources - the `res/drawable` half of the image contract
 * (the symbol half is the SF->Material map, `SystemSymbolResolver.kt`).
 *
 * Shared JSON names a catalog image with `assetName` (`Image`), `assetImage`
 * (`Button` / `Tab`), or `imageName` (`Label`). On Apple, `UIImage(named:)`
 * resolves that free-form string against `Assets.car` at runtime. Android's
 * `res/drawable` is the storage analog (density buckets, `-night` variants,
 * vector XML) but has no first-class runtime name lookup: drawables are
 * compile-time `R.drawable.*` constants, and the release resource shrinker
 * strips anything only reachable through a runtime string. This seam closes
 * that gap; see `Private/Android_Asset_Image_Design.md` for the full design.
 *
 * Two host mechanisms, composable because this is a `fun interface`:
 *
 *   * **Explicit map** ([imageRegistryOf]) - keys are the literal JSON strings
 *     (free-form Apple names are fine), values are `R.drawable` references.
 *     Compile-time references are shrink-proof by construction.
 *   * **Convention discovery** ([DiscoveringImageRegistry]) - zero-config:
 *     normalizes the name ([normalizeAssetDrawableName]) and looks up
 *     `aui_<normalized>` (then `<normalized>`) via `Resources.getIdentifier`.
 *     The library ships `res/raw/actionui_keep.xml` keeping `@drawable/aui_*`,
 *     so conventionally-named drawables survive resource shrinking with no
 *     host build changes. The optional `actionui-images.gradle` step generates
 *     such drawables from Apple-named source files at build time.
 *
 * Inject per call (`ActionUI.Render(images = ...)`) or globally
 * ([com.abracode.actionui.ActionUI.defaultImageRegistry]); the element tree
 * reads it through [LocalActionUIImageRegistry]. Without a registry,
 * asset-named images warn-and-skip.
 */
fun interface ActionUIImageRegistry {
    /** The drawable for an Apple asset-catalog [assetName], or `null` when unknown. */
    @DrawableRes
    fun drawableFor(assetName: String): Int?
}

/**
 * The common case: a fixed name -> `R.drawable` map.
 *
 * ```kotlin
 * ActionUI.Render(json, images = imageRegistryOf(
 *     "My Logo" to R.drawable.my_logo,
 *     "AppIcon-Dark" to R.drawable.app_icon_dark,
 * ))
 * ```
 */
fun imageRegistryOf(vararg entries: Pair<String, Int>): ActionUIImageRegistry {
    val map = mapOf(*entries)
    return ActionUIImageRegistry { name -> map[name] }
}

/** The drawable-name prefix of the discovery convention (and the shipped keep rule). */
const val AUI_DRAWABLE_PREFIX = "aui_"

/**
 * Normalizes a free-form Apple asset name to a legal Android resource name:
 * lowercased, every character outside `[a-z0-9_]` replaced with `_`
 * (`"My Logo"` / `"my.logo"` -> `"my_logo"`). The `actionui-images.gradle`
 * build step applies the same transform when generating drawables, so the
 * two sides meet on the same name. Lossy by design - distinct Apple names can
 * collide; prefer the explicit map when they do.
 */
fun normalizeAssetDrawableName(assetName: String): String =
    assetName.lowercase().map { if (it in 'a'..'z' || it in '0'..'9' || it == '_') it else '_' }
        .joinToString("")

/**
 * Convention-based discovery: resolves `aui_<normalized>` (the shipped
 * keep-rule convention), then bare `<normalized>`, via
 * `Resources.getIdentifier`. Results (including misses - the resource table
 * is fixed at build time) are cached, so the discouraged reflective lookup
 * runs once per distinct name.
 *
 * Drawables found through the *bare* name are NOT covered by the shipped
 * `aui_*` keep rule: a host using unprefixed names with resource shrinking
 * enabled must keep them itself (`tools:keep`).
 */
class DiscoveringImageRegistry(context: Context) : ActionUIImageRegistry {
    private val resources = context.resources
    private val packageName = context.packageName
    private val cache = mutableMapOf<String, Int?>()

    @DrawableRes
    override fun drawableFor(assetName: String): Int? = cache.getOrPut(assetName) {
        val normalized = normalizeAssetDrawableName(assetName)
        lookup(AUI_DRAWABLE_PREFIX + normalized) ?: lookup(normalized)
    }

    @DrawableRes
    @Suppress("DiscouragedApi")
    private fun lookup(name: String): Int? =
        resources.getIdentifier(name, "drawable", packageName).takeIf { it != 0 }
}

/**
 * The registry the element tree resolves asset-named images through; `null`
 * (the default) means the host supplied none and such images warn-and-skip.
 * Provided by `ActionUI.RenderWindow` from the `images` parameter.
 */
val LocalActionUIImageRegistry = staticCompositionLocalOf<ActionUIImageRegistry?> { null }
