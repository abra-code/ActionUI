package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Button as M3Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUIImageRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LabelIcon
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.selectLabelIcon
import com.abracode.actionui.Helpers.stringProperty

/**
 * Pull-down menu. Mirror of the Apple `Menu` element (`ActionUI/Views/Menu.swift`),
 * which wraps `SwiftUI.Menu`. Rendered with the native Material3 [DropdownMenu]:
 * a trigger button (the `title`) opens a dropdown whose items are built from the
 * `children`.
 *
 * Children are interpreted as menu items (not rendered as standalone views):
 *   * `Button`  -> a [DropdownMenuItem] showing the button's `title`; tapping it
 *     dispatches the button's `actionID` and dismisses the menu. An icon
 *     (`systemImage` / `materialName:android`, resolved through the shared
 *     `SymbolIcon` helper like `Button`) renders in the Material leading-icon slot.
 *   * `Divider` -> a [HorizontalDivider] between items.
 *   * `Section` -> its `header` as a (disabled) label item, then its `children` as
 *     nested items - a named group.
 *   * anything else -> a best-effort label item (warns); arbitrary view content in
 *     a menu has no Material analog.
 *
 * **Deferred vs. Apple.** The custom `label` trigger (a view shown instead of the
 * title - typically an SF Symbol like `ellipsis.circle`) is not supported yet: it
 * needs the `label` container and is usually an icon (the B2 image track). The
 * title is the trigger for now (defaulting to `"Menu"` when empty so the control
 * is visible). Nested submenus collapse to inline items.
 */
object Menu : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val title = element.properties?.stringProperty("title").orEmpty()
        val items = element.children.orEmpty()
        var expanded by remember { mutableStateOf(false) }

        Box(modifier = modifier) {
            // SwiftUI `.disabled` (set here or on any ancestor) -> M3 `enabled`.
            M3Button(onClick = { expanded = true }, enabled = LocalActionUIEnabled.current) {
                M3Text(title.ifEmpty { "Menu" })
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                items.forEach { child -> MenuChild(child, logger) { expanded = false } }
            }
        }
    }
}

/** Classifies a `Menu` child into the kind of menu item it produces. Pure, testable. */
internal enum class MenuItemKind { Action, Divider, Section, Other }

internal fun menuItemKind(child: ActionUIElement): MenuItemKind = when (child.type) {
    "Button" -> MenuItemKind.Action
    "Divider" -> MenuItemKind.Divider
    "Section" -> MenuItemKind.Section
    else -> MenuItemKind.Other
}

/**
 * Renders one menu child as item(s); [dismiss] closes the menu after an action.
 * Internal so the toolbar `secondaryAction` overflow can reuse it.
 *
 * Children are interpreted, not registry-built: a `Button` here is a semantic
 * action declaration (title / icon / `actionID`) whose presentation the menu
 * owns - a [DropdownMenuItem], not the filled `M3Button` the registry would
 * render. Same pattern as the toolbar chrome's `RenderChrome`
 * (`Helpers/ToolbarHelper.kt`), which documents the rationale.
 */
@Composable
internal fun MenuChild(child: ActionUIElement, logger: ActionUILogger, dismiss: () -> Unit) {
    when (menuItemKind(child)) {
        MenuItemKind.Action -> {
            val props = child.properties
            val label = props?.stringProperty("title").orEmpty()
            val actionID = props?.stringProperty("actionID")
            // A Button's icon (`systemImage` / `materialName:android`) renders in the
            // Material leading-icon slot, through the same glyph helper as `Button`.
            val imageRegistry = LocalActionUIImageRegistry.current
            val iconSource = remember(props, imageRegistry) { selectLabelIcon(props, "assetImage", "Menu item", logger, imageRegistry) }
            DropdownMenuItem(
                text = { M3Text(label) },
                leadingIcon = iconSource?.let { source ->
                    {
                        LabelIcon(
                            source = source,
                            imageScale = props?.stringProperty("imageScale"),
                            contentDescription = props?.stringProperty("accessibilityLabel"),
                            elementName = "Menu item",
                            logger = logger,
                        )
                    }
                },
                onClick = {
                    dismiss()
                    actionID?.let { ActionUIModel.actionHandler(it, viewID = child.id, viewPartID = 0) }
                },
            )
        }
        MenuItemKind.Divider -> HorizontalDivider()
        MenuItemKind.Section -> {
            child.properties?.stringProperty("header")?.let { header ->
                DropdownMenuItem(
                    text = { M3Text(header, style = MaterialTheme.typography.labelMedium) },
                    onClick = {},
                    enabled = false,
                )
            }
            child.children.orEmpty().forEach { MenuChild(it, logger, dismiss) }
        }
        MenuItemKind.Other -> {
            logger.log("Menu child '${child.type}' is not a menu item; showing a plain label", LoggerLevel.warning)
            val label = child.properties?.stringProperty("title")
                ?: child.properties?.stringProperty("text")
                ?: child.type
            DropdownMenuItem(text = { M3Text(label) }, onClick = { dismiss() })
        }
    }
}
