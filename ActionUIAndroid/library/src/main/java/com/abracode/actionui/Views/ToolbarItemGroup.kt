package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel

/**
 * A group of related toolbar items at one `placement`. Mirror of the Apple
 * `ToolbarItemGroup` element (`ActionUI/Views/ToolbarItemGroup.swift`): identical
 * to [ToolbarItem] except it carries `children` (an array) rather than a single
 * `content`, each placed at the group's `placement`. Consumed by the navigation
 * screen's `ToolbarHost` (`Helpers/ToolbarHelper.kt`); never rendered standalone.
 */
object ToolbarItemGroup : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        LocalActionUILogger.current.log(
            "ToolbarItemGroup is consumed by a toolbar; nothing is rendered standalone",
            LoggerLevel.debug,
        )
    }
}
