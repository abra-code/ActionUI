package com.abracode.actionui.Helpers

import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.sp
import com.abracode.actionui.Common.LoggerLevel

/**
 * Shared symbol-glyph rendering for ActionUI Android - the convergence point the
 * porting notes called for, so `Image`, `Label`, and Button image-labels draw an
 * SF Symbol (`systemName` / `systemImage`) or an explicit Material glyph
 * (`materialName`) through ONE path instead of each re-deriving icon handling
 * (mirrors how Apple resolves images centrally).
 *
 * Two layers:
 *   * [SymbolGlyph] - the low-level draw, given an already-resolved codepoint and
 *     axes. Sizes the glyph relative to the ambient font (scaled by `imageScale`)
 *     or an explicit sp size, and tints it with the inherited [LocalContentColor].
 *   * [SystemSymbolIcon] / [MaterialNameIcon] - resolve a name (SF or Material) to
 *     a codepoint + axes and draw via [SymbolGlyph], returning `false` (drawing
 *     nothing) when the name has no mapping so the caller can warn/skip.
 *
 * Axis resolution and sizing are the pure helpers in `ImageResolver.kt`
 * ([resolveSymbolWeight], [resolveSymbolFill], [resolveSymbolGrade],
 * [resolveSymbolSizeSp]); the actual glyph draw is [MaterialSymbolGlyph].
 */

/**
 * Draws a resolved symbol glyph (Material or SF), the shared tail of every icon
 * branch. Size mirrors SF Symbol image sizing - relative to the ambient font,
 * scaled by `imageScale` (cross-platform), or the explicit `materialSize` size in
 * sp; [tint] defaults to the inherited `foregroundStyle` ([LocalContentColor]).
 * The codepoint and axes are already resolved by the caller.
 */
@Composable
internal fun SymbolGlyph(
    codepoint: Int,
    weight: Int,
    fill: Float,
    grade: Int,
    explicitSizeSp: Float?,
    imageScale: String?,
    contentDescription: String?,
    tint: Color = LocalContentColor.current,
    modifier: Modifier = Modifier,
) {
    val ambientFontSizeSp = LocalTextStyle.current.fontSize
        .let { if (it.type == TextUnitType.Sp) it.value else null }
    val sizeSp = resolveSymbolSizeSp(
        explicitSizeSp = explicitSizeSp,
        imageScale = imageScale,
        inheritedFontSizeSp = ambientFontSizeSp,
    )
    MaterialSymbolGlyph(
        codepoint = codepoint,
        sizeSp = sizeSp.sp,
        tint = tint,
        weight = weight,
        fill = fill,
        grade = grade,
        contentDescription = contentDescription,
        modifier = modifier,
    )
}

/**
 * Resolves an SF Symbol [name] to a Material glyph via the bundled SF->Material
 * map ([systemSymbol]) and draws it, applying the precedence **explicit override
 * > per-row map tuning > default** for each axis. Returns `false` (drawing
 * nothing) when [name] has no mapping or the map asset is absent, so the caller
 * can warn/skip. The codepoint lookup is `remember`ed per name.
 */
@Composable
internal fun SystemSymbolIcon(
    name: String,
    explicitWeight: Int?,
    explicitFill: Float?,
    explicitGrade: Int?,
    explicitSizeSp: Float?,
    imageScale: String?,
    contentDescription: String?,
    tint: Color = LocalContentColor.current,
    modifier: Modifier = Modifier,
    logger: com.abracode.actionui.Common.ActionUILogger? = null,
): Boolean {
    val assets = LocalContext.current.assets
    val entry = remember(name, assets) { systemSymbol(name, assets, logger) } ?: return false
    SymbolGlyph(
        codepoint = entry.codepoint,
        weight = resolveSymbolWeight(explicitWeight, entry.weight),
        fill = resolveSymbolFill(explicitFill, entry.fill),
        grade = resolveSymbolGrade(explicitGrade),
        explicitSizeSp = explicitSizeSp,
        imageScale = imageScale,
        contentDescription = contentDescription,
        tint = tint,
        modifier = modifier,
    )
    return true
}

/**
 * Resolves an explicit Material Symbol [name] to a codepoint via the bundled
 * codepoints table ([materialCodepoint]) and draws it. Axes are explicit-or-default
 * (no per-row map tuning - that is the `systemName` path), pre-clamped by the
 * caller. Returns `false` (drawing nothing) when [name] is not a known Material
 * Symbol in the bundled font. The codepoint lookup is `remember`ed per name.
 */
@Composable
internal fun MaterialNameIcon(
    name: String,
    weight: Int,
    fill: Float,
    grade: Int,
    explicitSizeSp: Float?,
    imageScale: String?,
    contentDescription: String?,
    tint: Color = LocalContentColor.current,
    modifier: Modifier = Modifier,
    logger: com.abracode.actionui.Common.ActionUILogger? = null,
): Boolean {
    val assets = LocalContext.current.assets
    val codepoint = remember(name, assets) { materialCodepoint(name, assets, logger) } ?: return false
    SymbolGlyph(
        codepoint = codepoint,
        weight = weight,
        fill = fill,
        grade = grade,
        explicitSizeSp = explicitSizeSp,
        imageScale = imageScale,
        contentDescription = contentDescription,
        tint = tint,
        modifier = modifier,
    )
    return true
}

/**
 * Draws the leading / standalone icon for an image-label control (`Label`,
 * `Button`, `NavigationLink`, `Tab`, `ContentUnavailableView`) from an
 * already-picked [source] ([selectLabelIcon]). The single place the whole
 * `systemImage` family converges, so each element is one call rather than its own
 * copy of the `when` + warn-on-unknown-name block. (`Image` keeps its own branches
 * - its source keys are `systemName` / `materialName`, not `systemImage`.)
 *
 * [defaultSizeSp] sizes the glyph when the JSON gives no explicit `materialSize`,
 * for a context that should not track a surrounding font (a nav-bar item, a
 * hero icon). `null` keeps the ambient-font sizing inline labels use.
 *
 * Returns `true` iff an icon was actually drawn - an unknown glyph name warns
 * (deduped by `remember`) and draws nothing, `null`/raster draws nothing - so
 * the caller can place inter-element spacing only when there is really an icon.
 * A [ImageSource.DrawableResource] (registry-resolved asset icon) draws as-is,
 * untinted, in the glyph-sized box.
 */
@Composable
internal fun LabelIcon(
    source: ImageSource?,
    imageScale: String?,
    contentDescription: String?,
    elementName: String,
    defaultSizeSp: Float? = null,
    tint: Color = LocalContentColor.current,
    modifier: Modifier = Modifier,
    logger: com.abracode.actionui.Common.ActionUILogger? = null,
): Boolean {
    when (source) {
        is ImageSource.MaterialSymbol -> {
            val rendered = MaterialNameIcon(
                name = source.name,
                weight = source.weight,
                fill = source.fill,
                grade = source.grade,
                explicitSizeSp = source.explicitSizeSp ?: defaultSizeSp,
                imageScale = imageScale,
                contentDescription = contentDescription,
                tint = tint,
                modifier = modifier,
                logger = logger,
            )
            if (!rendered) {
                remember(source, elementName) {
                    logger?.log(
                        "$elementName materialName '${source.name}' is not a known " +
                            "Material Symbol in the bundled font. Icon omitted.",
                        LoggerLevel.warning,
                    )
                }
            }
            return rendered
        }

        is ImageSource.SystemSymbol -> {
            val rendered = SystemSymbolIcon(
                name = source.name,
                explicitWeight = source.explicitWeight,
                explicitFill = source.explicitFill,
                explicitGrade = source.explicitGrade,
                explicitSizeSp = source.explicitSizeSp ?: defaultSizeSp,
                imageScale = imageScale,
                contentDescription = contentDescription,
                tint = tint,
                modifier = modifier,
                logger = logger,
            )
            if (!rendered) {
                remember(source, elementName) {
                    logger?.log(
                        "$elementName systemImage '${source.name}' has no SF->Material " +
                            "mapping (or the map asset is absent). Icon omitted; add " +
                            "'materialName:android' for an explicit Android glyph.",
                        LoggerLevel.warning,
                    )
                }
            }
            return rendered
        }

        is ImageSource.DrawableResource -> {
            // Asset-catalog icon (Label imageName / Button-Tab assetImage)
            // resolved to res/drawable by the host registry. Drawn as-is (no
            // tint - the registry cannot know whether a drawable is a template
            // image), sized to the same box a glyph would get so it sits
            // correctly beside the title.
            val ambientFontSizeSp = LocalTextStyle.current.fontSize
                .let { if (it.type == TextUnitType.Sp) it.value else null }
            val sizeSp = resolveSymbolSizeSp(
                explicitSizeSp = defaultSizeSp,
                imageScale = imageScale,
                inheritedFontSizeSp = ambientFontSizeSp,
            )
            val sizeDp = with(LocalDensity.current) { sizeSp.sp.toDp() }
            FoundationImage(
                painter = painterResource(source.resId),
                contentDescription = contentDescription,
                modifier = modifier.size(sizeDp),
            )
            return true
        }

        // null -> title-only; raster kinds are never produced by selectLabelIcon.
        else -> return false
    }
}
