package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Renders nothing. Mirror of the Apple `EmptyView` element
 * (`ActionUI/Views/EmptyView.swift`), which wraps `SwiftUI.EmptyView`, and the
 * fallback the renderer uses where SwiftUI would substitute an `EmptyView` (e.g.
 * a [Link] / [ShareLink] with no valid URL).
 *
 * An `EmptyView` produces no layout node, so the base [modifier] has nothing to
 * attach to and is intentionally unused - matching the Apple element, where a
 * modifier on an `EmptyView` likewise produces nothing visible.
 */
object EmptyView : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        // Intentionally empty: renders nothing.
    }
}
