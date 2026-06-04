package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel

/**
 * Multi-column data table. The Apple `Table` element
 * (`ActionUI/Views/Table.swift`) is **macOS-only** - SwiftUI's `Table` exists on
 * AppKit, and on every other platform the Apple element itself returns
 * `SwiftUI.EmptyView()`. Android has no native multi-column table primitive and
 * is the "every other platform" case, so this builder renders **nothing**,
 * matching the Apple `#else` branch.
 *
 * It is registered (so a cross-platform document referencing `Table` resolves and
 * does not warn as an unknown type) and produces no layout node; the base
 * modifier therefore has nothing to attach to and is intentionally unused.
 * Authors targeting Android should use a `List` (template mode) for tabular data.
 */
object Table : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        LocalActionUILogger.current.log(
            "Table is macOS-only; renders nothing on Android (use a List for tabular data)",
            LoggerLevel.debug,
        )
    }
}
