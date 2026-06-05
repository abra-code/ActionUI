package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel

/**
 * A single toolbar item at a `placement`. Mirror of the Apple `ToolbarItem`
 * element (`ActionUI/Views/ToolbarItem.swift`). It is **not** a standalone view:
 * it lives in an element's `toolbar` array, carries a `placement` property and a
 * single `content` view, and is consumed by the navigation screen's `ToolbarHost`
 * (`Helpers/ToolbarHelper.kt`). Registered so a cross-platform document resolves
 * it and its `content` gets a `ViewModel`; rendered standalone it produces nothing
 * (like `Tab`/`Table`).
 */
object ToolbarItem : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        LocalActionUILogger.current.log(
            "ToolbarItem is consumed by a toolbar; nothing is rendered standalone",
            LoggerLevel.debug,
        )
    }
}
