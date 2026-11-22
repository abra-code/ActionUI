package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUICapability
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.LocalJSONContentOrigin
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.subElements

/**
 * Presents the **element-level** modal subviews - the `sheet` / `fullScreenCover`
 * keys any element may declare in JSON - the Android counterpart of the
 * `SheetModifierView` / `FullScreenCoverModifierView` wrappers Apple's
 * `View.swift` `applyModifiers` attaches (`ActionUI/Helpers/SheetHelper.swift`).
 * This is the primary authoring pattern for modals; the *window-level* host API
 * (`ActionUIModel.presentModal` -> [WindowModalHost]) remains the detached tier.
 *
 * **Why one window-level host instead of per-element wrappers.** SwiftUI's
 * `.sheet` is a view modifier, so Apple wraps each carrier view. In Compose a
 * `ModalBottomSheet` / `Dialog` is a window-scoped overlay no matter where it is
 * composed, so wrapping at each of the ~20 container child-loop call sites would buy
 * nothing. Instead `ActionUI.RenderWindow` places a single [ElementModalsHost]
 * beside [WindowDialogHost] / [WindowModalHost]; it walks the document once
 * ([collectModalCarriers], pure and testable) and observes every carrier's
 * presentation state. A bonus over per-element composition: a carrier inside a
 * lazy container that is scrolled out of composition can still present.
 *
 * **Presentation state - Apple contract, key for key.** A carrier element's
 * [com.abracode.actionui.Common.ViewModel] holds `states["sheetVisible"]` /
 * `states["fullScreenCoverVisible"]` (Booleans, Compose snapshot state). They
 * flip true from a `Button` tap when the Button itself carries the subview
 * (`Views/Button.kt`, mirroring `Button.swift`), or from the host via
 * `ActionUIModel.setElementState(viewID, "sheetVisible", true)`. Dismissal:
 * scrim tap / swipe-down for the sheet, back press for the cover (as on iOS a
 * cover has no swipe-to-dismiss), or the host setting the state false.
 * `sheetOnDismissActionID` / `fullScreenCoverOnDismissActionID` fire on the
 * visible -> hidden transition, so user and programmatic dismissals both report,
 * like SwiftUI's `onDismiss`.
 *
 * Style mapping (native-first, same as [WindowModalHost]): `sheet` -> Material3
 * [ModalBottomSheet]; `fullScreenCover` -> a full-screen [Dialog]
 * (`usePlatformDefaultWidth = false` + a fill-size [Surface]).
 *
 * **Not covered** (parity with the registration walk): a `sheet` declared inside
 * a `template` repeater - template instances are throw-away renders without
 * registered [com.abracode.actionui.Common.ViewModel]s, so they have no states to
 * observe (the same is true on Apple). `popover` stays deferred - no Android
 * popover subsystem yet.
 */
@Composable
fun ElementModalsHost(root: ActionUIElement) {
    val carriers = remember(root) { collectModalCarriers(root) }
    if (carriers.isEmpty()) return
    // A less-trusted window document (from a server, or from a file outside the app's
    // resources) presents no sheet or cover of its own over the window.
    if (!ActionUIModel.allows(ActionUICapability.PresentModal, LocalJSONContentOrigin.current)) {
        val logger = LocalActionUILogger.current
        LaunchedEffect(carriers) {
            carriers.forEach {
                logger.log("Not presenting a sheet or cover for element ${it.id}: the trust policy refuses it", LoggerLevel.warning)
            }
        }
        return
    }
    carriers.forEach { ElementModal(it) }
}

/** The `states` key gating an element-level sheet; Apple's `SheetHelper.swift` key. */
const val SHEET_VISIBLE_STATE_KEY = "sheetVisible"

/** The `states` key gating an element-level full-screen cover (Apple parity). */
const val FULL_SCREEN_COVER_VISIBLE_STATE_KEY = "fullScreenCoverVisible"

/**
 * Walks the document and returns every element carrying a `sheet` or
 * `fullScreenCover` subview, in tree order. Traverses [subElements], so modal
 * content is itself walked (a sheet may open from inside a sheet) while
 * `template` stays excluded by design.
 */
internal fun collectModalCarriers(root: ActionUIElement): List<ActionUIElement> = buildList {
    fun walk(element: ActionUIElement) {
        if (element.sheet != null || element.fullScreenCover != null) add(element)
        element.subElements().forEach { walk(it) }
    }
    walk(root)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ElementModal(element: ActionUIElement) {
    val windowModel = LocalWindowModel.current ?: return
    val carrierModel = windowModel.viewModels[element.id] ?: return
    val logger = LocalActionUILogger.current

    element.sheet?.let { sheetElement ->
        val visible = carrierModel.states[SHEET_VISIBLE_STATE_KEY] as? Boolean ?: false
        FireOnDismiss(visible, element, "sheetOnDismissActionID")
        if (visible) {
            ModalBottomSheet(
                onDismissRequest = { carrierModel.states[SHEET_VISIBLE_STATE_KEY] = false },
            ) {
                ClearPersistentToolbarItems { ElementContent(sheetElement, logger) }
            }
        }
    }

    element.fullScreenCover?.let { coverElement ->
        val visible = carrierModel.states[FULL_SCREEN_COVER_VISIBLE_STATE_KEY] as? Boolean ?: false
        FireOnDismiss(visible, element, "fullScreenCoverOnDismissActionID")
        if (visible) {
            Dialog(
                onDismissRequest = { carrierModel.states[FULL_SCREEN_COVER_VISIBLE_STATE_KEY] = false },
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) {
                Surface(Modifier.fillMaxSize()) {
                    ClearPersistentToolbarItems { ElementContent(coverElement, logger) }
                }
            }
        }
    }
}

/**
 * Fires the carrier's on-dismiss action on the visible -> hidden transition.
 * Watching the transition (rather than hooking only `onDismissRequest`) makes a
 * host-side `setElementState(..., false)` report too, like SwiftUI `onDismiss`.
 */
@Composable
private fun FireOnDismiss(visible: Boolean, element: ActionUIElement, propertyKey: String) {
    val actionID = element.properties?.stringProperty(propertyKey)
    val dispatch = rememberActionDispatch()
    var wasVisible by remember { mutableStateOf(visible) }
    LaunchedEffect(visible) {
        if (wasVisible && !visible && actionID != null) {
            dispatch.fire(actionID, viewID = element.id, viewPartID = 0)
        }
        wasVisible = visible
    }
}
