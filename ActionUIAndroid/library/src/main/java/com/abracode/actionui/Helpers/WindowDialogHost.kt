package com.abracode.actionui.Helpers

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.DialogButton
import com.abracode.actionui.Common.DialogButtonRole
import com.abracode.actionui.Common.DialogStyle
import com.abracode.actionui.Common.WindowDialog
import com.abracode.actionui.Common.WindowModel

/**
 * Renders [windowModel]'s active [WindowDialog] (alert / confirmationDialog) over the
 * window root - the Android counterpart of the dialog half of Apple's
 * `WindowModalView`. `ActionUI`'s `RenderWindow` places one of these in every
 * top-level window, so it observes that window's [WindowModel.windowDialog] (Compose
 * snapshot state) and appears the moment a host handler calls
 * `ActionUIModel.presentAlert` / `presentConfirmationDialog`.
 *
 * Tapping a button fires its `actionID` (if any) through
 * [ActionUIModel.actionHandler] and then dismisses; a scrim / swipe / back dismiss
 * clears the dialog without firing an action (matching Apple's `dismissDialog`, where
 * SwiftUI's binding setter calls it).
 *
 * Style mapping (native-first): the two styles map to *different* native containers,
 * because Android splits what iOS expresses with one action sheet into two idioms.
 *   * [DialogStyle.ALERT] -> Material3 [AlertDialog]. Its buttons sit in the dialog's
 *     trailing action row (end-aligned, the native placement for alert actions); a
 *     [DialogButtonRole.DESTRUCTIVE] button shows in the error color.
 *   * [DialogStyle.CONFIRMATION_DIALOG] (an iOS action sheet - a list of *choices*,
 *     not a pair of alert actions) -> a Material3 [ModalBottomSheet] of full-width,
 *     leading-aligned rows. This, not an end-aligned button cluster, is what Android
 *     users see when an app offers a contextual list of options. A
 *     [DialogButtonRole.CANCEL] row is set off from the choices by a divider, the
 *     closest native echo of the cancel button SwiftUI separates and emphasizes.
 */
@Composable
fun WindowDialogHost(windowModel: WindowModel) {
    val dialog = windowModel.windowDialog ?: return
    val windowUUID = windowModel.windowUUID

    if (dialog.style == DialogStyle.CONFIRMATION_DIALOG) {
        ConfirmationSheet(dialog, windowUUID)
    } else {
        AlertDialog(
            onDismissRequest = { ActionUIModel.dismissDialog(windowUUID) },
            title = { Text(dialog.title) },
            text = dialog.message?.let { message -> { Text(message) } },
            confirmButton = {
                Row(horizontalArrangement = Arrangement.End) {
                    dialog.buttons.forEach { AlertButton(it, windowUUID) }
                }
            },
        )
    }
}

/**
 * The confirmation-dialog (action sheet) presentation: a [ModalBottomSheet] whose
 * title block tops a stack of full-width, leading-aligned action rows. A scrim /
 * swipe-down dismiss clears the dialog without firing (Apple's `dismissDialog`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConfirmationSheet(dialog: WindowDialog, windowUUID: String) {
    ModalBottomSheet(onDismissRequest = { ActionUIModel.dismissDialog(windowUUID) }) {
        Column(Modifier.fillMaxWidth()) {
            Text(
                dialog.title,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 12.dp),
            )
            dialog.message?.let { message ->
                Text(
                    message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .padding(bottom = 12.dp),
                )
            }
            HorizontalDivider()
            dialog.buttons.forEachIndexed { index, button ->
                // Set a cancel row off from the choices above it, as an action sheet does.
                if (button.role == DialogButtonRole.CANCEL && index > 0) HorizontalDivider()
                SheetActionRow(button, windowUUID)
            }
        }
    }
}

/** One full-width action-sheet row: fires its `actionID` (if any), then dismisses. */
@Composable
private fun SheetActionRow(button: DialogButton, windowUUID: String) {
    Text(
        text = button.title,
        color = dialogButtonColor(button),
        style = MaterialTheme.typography.bodyLarge,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { fireAndDismiss(button, windowUUID) }
            .padding(horizontal = 24.dp, vertical = 16.dp),
    )
}

/** One alert action button in the trailing row: fires its `actionID`, then dismisses. */
@Composable
private fun AlertButton(button: DialogButton, windowUUID: String) {
    TextButton(onClick = { fireAndDismiss(button, windowUUID) }) {
        Text(button.title, color = dialogButtonColor(button))
    }
}

/** A destructive button shows in the error color; everything else inherits. */
@Composable
private fun dialogButtonColor(button: DialogButton): Color =
    if (button.role == DialogButtonRole.DESTRUCTIVE) MaterialTheme.colorScheme.error
    else Color.Unspecified

/** Fires [button]'s `actionID` (if any) through the action layer, then dismisses. */
private fun fireAndDismiss(button: DialogButton, windowUUID: String) {
    button.actionID?.let {
        ActionUIModel.actionHandler(
            actionID = it,
            windowUUID = windowUUID,
            viewID = 0,
            viewPartID = 0,
            context = null,
        )
    }
    ActionUIModel.dismissDialog(windowUUID)
}
