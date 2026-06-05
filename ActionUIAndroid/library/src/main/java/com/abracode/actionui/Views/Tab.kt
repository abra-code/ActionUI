package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.stringProperty

/**
 * A single tab's configuration. Mirror of the Apple `Tab` element
 * (`ActionUI/Views/Tab.swift`): it is **not** a standalone view - it carries a
 * tab's metadata (`title`, `systemImage`/`assetImage`, `badge`) in `properties`
 * and the tab body in `content`, and is only meaningful inside a [TabView]'s
 * `children`. Registered so a cross-platform document resolves it; rendered
 * standalone it produces nothing (matching Apple's `EmptyView()`).
 */
object Tab : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        LocalActionUILogger.current.log(
            "Tab is only meaningful inside a TabView; nothing is rendered standalone",
            LoggerLevel.debug,
        )
    }
}

/** A tab's label text, defaulting to `"Tab"` (matches Apple's title fallback). */
internal fun tabTitle(tab: ActionUIElement): String =
    tab.properties?.stringProperty("title") ?: "Tab"
