package com.abracode.actionui.Helpers

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.OpenURLObserver
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The base lifecycle action hooks - the Android counterpart of the three
 * view-based hook modifiers in Apple's `View.swift`:
 *
 *   * `onAppearActionID`    - SwiftUI `.onAppear`: fires once when the element
 *     enters the composition.
 *   * `onDisappearActionID` - SwiftUI `.onDisappear`: fires once when it
 *     leaves.
 *   * `openURLActionID`     - SwiftUI `.onOpenURL`: fires when the host
 *     delivers an incoming URL via [ActionUIModel.onOpenURL] (the Android
 *     analog of the system delivering a deep link to the scene), with the URL
 *     string as `context`.
 *
 * All three resolve at the shared build entry point
 * (`ViewModifierHelper.BuildViewWithModifiers`), so every rendered element -
 * container child, window root, navigation screen, modal, toolbar item -
 * carries them; the per-row `template` path is excluded, as it is for the
 * other view-based modifiers (popover, decorations).
 *
 * **Appearance = composition.** Compose has no SwiftUI-style appearance
 * callback; entering/leaving the composition is the analog, and it agrees
 * with SwiftUI where it matters: a lazy container (`List`, `LazyVStack`)
 * composes rows as they scroll in and disposes them as they scroll out,
 * firing the hooks per entry/exit exactly as SwiftUI's `List` does. In a
 * non-lazy `ScrollView` both platforms fire `onAppear` for offscreen children
 * up front.
 *
 * **`onOpenURL` parity.** Only elements currently composed receive a URL
 * (each registers an [OpenURLObserver] for its composition lifetime), exactly
 * SwiftUI's contract that `.onOpenURL` handlers exist while their view does.
 * No element `id` is required - the observer captures the actionID directly.
 */
@Composable
internal fun ElementActionHooks(element: ActionUIElement) {
    val properties = element.properties
    val logger = LocalActionUILogger.current
    val onAppearActionID = resolveActionHookID(properties, "onAppearActionID", logger)
    val onDisappearActionID = resolveActionHookID(properties, "onDisappearActionID", logger)
    val openURLActionID = resolveActionHookID(properties, "openURLActionID", logger)
    if (onAppearActionID == null && onDisappearActionID == null && openURLActionID == null) return

    val windowUUID = LocalWindowModel.current?.windowUUID ?: ""

    if (onAppearActionID != null || onDisappearActionID != null) {
        // A property override may retarget the disappear actionID after entry;
        // fire the latest value on exit (the appear side is by nature the
        // value at entry).
        val currentDisappearID by rememberUpdatedState(onDisappearActionID)
        DisposableEffect(element.id) {
            onAppearActionID?.let {
                ActionUIModel.actionHandler(it, windowUUID = windowUUID, viewID = element.id, viewPartID = 0, context = null)
            }
            onDispose {
                currentDisappearID?.let {
                    ActionUIModel.actionHandler(it, windowUUID = windowUUID, viewID = element.id, viewPartID = 0, context = null)
                }
            }
        }
    }

    if (openURLActionID != null) {
        DisposableEffect(openURLActionID, windowUUID, element.id) {
            val observer = OpenURLObserver(openURLActionID, windowUUID, element.id)
            ActionUIModel.registerOpenURLObserver(observer)
            onDispose { ActionUIModel.unregisterOpenURLObserver(observer) }
        }
    }
}

/**
 * Reads the action-hook property [key] off [properties], warning on a
 * non-String value (`View.swift` validation parity). Returns the actionID or
 * null.
 */
internal fun resolveActionHookID(
    properties: JsonObject?,
    key: String,
    logger: ActionUILogger? = null,
): String? {
    val raw = properties?.get(key) ?: return null
    val value = (raw as? JsonPrimitive)?.takeIf { it.isString }?.content
    if (value == null) {
        logger?.log("Invalid type for $key: expected String, ignoring", LoggerLevel.warning)
    }
    return value
}
