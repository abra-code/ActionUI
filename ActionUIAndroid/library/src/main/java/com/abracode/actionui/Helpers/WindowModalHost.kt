package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.ModalStyle
import com.abracode.actionui.Common.WindowModel

/**
 * Renders [windowModel]'s active WindowModal (sheet / fullScreenCover) over the
 * window root - the Android counterpart of the modal half of Apple's
 * `WindowModalView`. `ActionUI`'s `RenderWindow` places one of these in every
 * top-level window, so it observes that window's [WindowModel.windowModal] (Compose
 * snapshot state) and appears the moment a host handler calls
 * `ActionUIModel.presentModal`.
 *
 * The loaded sub-document is built through the registry exactly like the window
 * root (its [ViewModel]s were already merged into the window pool by
 * `presentModal`, so value-bearing controls inside the modal resolve against
 * [com.abracode.actionui.Common.LocalWindowModel], which Compose propagates into the
 * sheet / dialog sub-composition).
 *
 * Style mapping (native-first):
 *   * [ModalStyle.SHEET] -> Material3 [ModalBottomSheet] (the Android analog of a
 *     SwiftUI `.sheet`); a scrim / swipe-down dismiss calls `dismissModal`.
 *   * [ModalStyle.FULL_SCREEN_COVER] -> a full-screen [Dialog] (`usePlatformDefaultWidth
 *     = false` + a fill-size `Surface`); a back press dismisses. As on iOS there is
 *     no swipe-to-dismiss, so a cover document should provide its own close action
 *     (which the host routes to `dismissModal`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WindowModalHost(windowModel: WindowModel) {
    val modal = windowModel.windowModal ?: return
    val logger = LocalActionUILogger.current
    val windowUUID = windowModel.windowUUID
    val dismiss = { ActionUIModel.dismissModal(windowUUID) }

    when (modal.style) {
        ModalStyle.SHEET -> ModalBottomSheet(onDismissRequest = dismiss) {
            ElementContent(modal.element, logger)
        }

        ModalStyle.FULL_SCREEN_COVER -> Dialog(
            onDismissRequest = dismiss,
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(Modifier.fillMaxSize()) {
                ElementContent(modal.element, logger)
            }
        }
    }
}

/**
 * Builds a subview root element through the registry, like the window root.
 * Shared by the window/element modals (`ElementModalHost.kt`), the popover
 * (`PopoverHelper.kt`), and the overlay/background decorations
 * (`ViewModifierHelper.kt`, which supplies the alignment [modifier]).
 */
@Composable
internal fun ElementContent(
    element: ActionUIElement,
    logger: ActionUILogger,
    modifier: Modifier = Modifier,
) {
    val builder = ActionUIRegistry.lookup(element.type) ?: return
    ProvideTextStyleEnvironment(element.properties, logger) {
        builder.BuildViewWithModifiers(element, modifier)
    }
}
