package com.abracode.actionui.Views

import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis

/**
 * Renders a thin separator line between sibling elements.
 *
 * Mirror of the Apple `Divider` element (`ActionUI/Views/Divider.swift`), which
 * wraps `SwiftUI.Divider()`. SwiftUI's divider adapts to its container — a
 * horizontal rule inside a `VStack`, a vertical rule inside an `HStack`. Compose
 * has no such inference, so this builder reads [LocalStackAxis] (provided by
 * [VStack] / [HStack]) to pick the matching composable:
 *
 *   * inside a vertical stack ([StackAxis.Vertical]) → [HorizontalDivider]
 *   * inside a horizontal stack ([StackAxis.Horizontal]) → [VerticalDivider]
 *
 * With no enclosing stack the axis defaults to [StackAxis.Vertical], yielding a
 * horizontal rule — SwiftUI's default for a standalone divider.
 *
 * Carries no properties of its own; the universal modifiers from
 * `applyCommonProperties` arrive via [modifier].
 *
 * Sample JSON: `{ "type": "Divider" }`
 */
object Divider : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        when (LocalStackAxis.current) {
            StackAxis.Vertical   -> HorizontalDivider(modifier = modifier)
            StackAxis.Horizontal -> VerticalDivider(modifier = modifier)
        }
    }
}
