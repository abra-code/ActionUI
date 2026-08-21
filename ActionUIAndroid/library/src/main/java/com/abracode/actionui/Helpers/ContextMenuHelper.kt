package com.abracode.actionui.Helpers

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.applyOuterProperties
import com.abracode.actionui.Views.MenuChild

/**
 * The `contextMenu` modifier - the Android mirror of Apple's `.contextMenu`
 * (`View.swift` applyModifiers, `Helpers/ContextMenuHelper.swift`).
 *
 * **Why two subview slots, not a property array.** SwiftUI's
 * `.contextMenu(menuItems:preview:)` is itself two ViewBuilders: a menu of action
 * items, and an optional arbitrary "preview" card. ActionUI models it the same way -
 * `contextMenu` is an array subview of real menu-item elements (Button / Divider /
 * Section, each carrying its own title / systemImage / role / actionID) and
 * `contextMenuPreview` is an optional single arbitrary subview. Real element subtrees
 * let a designer place any views (an Image preview, an HStack of items), not buttons
 * synthesized from a flat descriptor array.
 *
 * **Trigger is the platform idiom, not a port.** Apple opens on a long-press (iOS) /
 * right-click (macOS); the Android idiom is a long-press that floats a Material
 * [DropdownMenu] anchored to the element ([combinedClickable]'s `onLongClick`). The
 * action items reuse `Menu`'s [MenuChild] interpretation (a Button becomes a native
 * `DropdownMenuItem`); the preview - which on iOS lifts above the menu - has no native
 * Android equivalent, so its subtree renders as a block atop the menu ([ElementContent]),
 * the platform-idiom adaptation.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ActionUIViewConstruction.BuildViewWithContextMenu(
    element: ActionUIElement,
    modifier: Modifier,
    animator: ElementAnimator?,
) {
    val logger = LocalActionUILogger.current
    val items = element.contextMenu.orEmpty()
    val preview = element.contextMenuPreview
    var expanded by remember { mutableStateOf(false) }

    Box(
        modifier
            .applyOuterProperties(element.properties, logger, animator)
            .combinedClickable(
                // Gated so a disabled - or hidden - element neither opens its menu nor
                // eats the plain tap meant for whatever is behind it.
                enabled = LocalActionUIEnabled.current,
                interactionSource = remember { MutableInteractionSource() },
                indication = null, // no ripple on the whole element; the menu is the feedback
                onLongClick = { expanded = true },
                onClick = {},
            )
    ) {
        BuildViewWithDecorations(element, Modifier, animator)
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            // The preview subtree (when present) renders above the action items - the
            // Android stand-in for the iOS lift-and-enlarge preview.
            preview?.let {
                ElementContent(it, logger)
                HorizontalDivider()
            }
            items.forEach { item ->
                MenuChild(item, logger, dismiss = { expanded = false })
            }
        }
    }
}
