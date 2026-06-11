package com.abracode.actionui.Common

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json

/**
 * The decoder configuration shared by every ActionUI document entry point
 * (`ActionUI.Render` roots, `ActionUIModel.presentModal` sub-documents,
 * `LoadableView` includes), so all paths accept exactly the same documents.
 *
 * - `ignoreUnknownKeys`: a document may carry keys this renderer does not know
 *   (newer schema, other platforms' suffixed keys); they are skipped, not fatal.
 * - `allowTrailingComma`: Apple's Foundation JSON parser accepts a trailing
 *   comma before `}` / `]`, and documents authored against the Swift framework
 *   rely on that leniency (the verifier strips trailing commas for the same
 *   reason - see `_strip_jsonc` in `Tools/verifier/validate_actionui.py`).
 *   Matching it keeps "renders on Apple" implying "decodes on Android".
 */
@OptIn(ExperimentalSerializationApi::class)
internal val ActionUIJson: Json = Json {
    ignoreUnknownKeys = true
    allowTrailingComma = true
}
