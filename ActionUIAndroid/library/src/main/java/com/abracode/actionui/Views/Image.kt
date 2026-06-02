package com.abracode.actionui.Views

import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Helpers.loadImagePainter
import com.abracode.actionui.Helpers.resolveContentScale
import com.abracode.actionui.Helpers.selectImageSource
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a bundled image from the app's `assets/` directory or a filesystem
 * path.
 *
 * Mirror of the Apple `Image` element (`ActionUI/Views/Image.swift`). The
 * source-selection, scaling, and decoding logic lives in the shared
 * `ImageResolver` seam (`Common/ImageResolver.kt`) so this builder stays thin
 * and so `Label` / `Button` image labels can converge on the same resolver
 * later.
 *
 * **Supported sources (Phase 1, no new dependencies).**
 *   * `resourceName` -> a file in `assets/` (e.g. `"logo.png"`), decoded as a raster.
 *   * `filePath`     -> an absolute filesystem path to a raster image.
 *
 * **Deferred vs. Apple** (warn-and-skip, not silent - an Image with an
 * unresolvable source renders nothing):
 *   * `assetName`  -> Android `res/drawable`; pending a name->resource contract.
 *   * `systemName` -> SF Symbol; no portable Android name lookup.
 *
 * **Scaling.** `contentMode` (`fit`/`fill`) maps
 * to a Compose `ContentScale` via [resolveContentScale]; default is fit.
 * `imageScale` (SF-Symbol-only on Apple) is ignored until symbols land.
 *
 * **Accessibility.** `accessibilityLabel` is forwarded as the composable's
 * `contentDescription`.
 *
 * Sample JSON:
 * ```
 * { "type": "Image", "properties": { "resourceName": "logo.png", "contentMode": "fit" } }
 * ```
 */
object Image : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val context = LocalContext.current

        // Source selection (+ its warnings) and the decode/I/O run once per
        // properties change, not per recomposition.
        val source = remember(props) { selectImageSource(props, logger) }
        val painter = remember(source, context) {
            source?.let { loadImagePainter(it, context, logger) }
        }

        // Unresolvable source -> render nothing (the warning was already logged).
        // Diverges from Apple, which falls back to an SF-Symbol "photo"
        // placeholder; Android has no built-in equivalent drawable.
        if (painter == null) return

        FoundationImage(
            painter = painter,
            contentDescription = props?.stringProperty("accessibilityLabel"),
            modifier = modifier,
            contentScale = resolveContentScale(props, logger)
        )
    }
}
