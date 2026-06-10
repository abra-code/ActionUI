package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Helpers.LabelIcon
import com.abracode.actionui.Helpers.selectLabelIcon
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a title paired with a leading icon - the Android mirror of the Apple
 * `Label` element (`ActionUI/Views/Label.swift`), which maps to SwiftUI `Label`.
 *
 * SwiftUI's `Label(title, systemImage:)` lays an icon before its title; with no
 * image it collapses to `.titleOnly`. This builder does the same: a `Row` of an
 * optional glyph icon and the title text, both inheriting the ambient `font` /
 * `foregroundStyle` (so the icon and text match), with the universal modifiers
 * (padding, frame, background, ...) applied to the row via [modifier].
 *
 * **Icon source.** The icon resolves through the shared `SymbolIcon` seam, the
 * same glyph path as `Image`:
 *   * `systemImage`          -> an SF Symbol, mapped to the closest Material glyph
 *     via the bundled SF->Material map. This is the Apple-canonical key; shared
 *     cross-platform JSON needs nothing else.
 *   * `materialName:android` -> an explicit Material Symbol (the Android escape
 *     hatch), winning over `systemImage` when both are present.
 *   * Axis overrides `materialWeight` / `materialFill` / `materialGrade` /
 *     `materialSize` (`:android`) and `imageScale` tune the glyph, exactly as on
 *     `Image`.
 *
 * **Deferred vs. Apple** (warn-and-skip, not silent): `imageName` (asset-catalog
 * image) maps to an Android `res/drawable` resource, pending the same
 * name->resource contract `Image`'s `assetName` waits on. A `Label` carrying only
 * `imageName` renders title-only with one warning.
 *
 * **Accessibility.** `accessibilityLabel` (and the other universal
 * accessibility properties) arrive on [modifier] via the shared pipeline
 * (`ModifierResolver.applyCommonProperties`); the icon's `contentDescription`
 * stays null so the label is not announced a second time on the glyph node.
 *
 * Sample JSON:
 * ```
 * { "type": "Label", "properties": { "title": "Favorites",
 *   "systemImage": "star.fill", "foregroundStyle": "orange" } }
 * ```
 */
object Label : ActionUIViewConstruction {

    /** Gap between the icon and the title, approximating SwiftUI `Label` spacing. */
    private val IconGap = 6.dp

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val title = props?.stringProperty("title") ?: ""
        val imageScale = props?.stringProperty("imageScale")

        // Icon selection (+ its deferred-source warning) runs once per change. A
        // null result is title-only (not an error), unlike Image's no-source case.
        val iconSource = remember(props) { selectLabelIcon(props, "imageName", "Label", logger) }

        Row(
            modifier = modifier,
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(IconGap),
        ) {
            // Shared glyph seam: draws nothing (and warns) on an unknown name, and
            // composes no node when there is no icon, so spacedBy adds no phantom gap.
            LabelIcon(
                source = iconSource,
                imageScale = imageScale,
                contentDescription = null,
                elementName = "Label",
                logger = logger,
            )

            if (title.isNotEmpty()) {
                M3Text(text = title)
            }
        }
    }
}
