package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Spacer as LayoutSpacer
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Renders flexible empty space that pushes sibling elements apart.
 *
 * Mirror of the Apple `Spacer` element (`ActionUI/Views/Spacer.swift`), which
 * wraps `SwiftUI.Spacer()`. SwiftUI's spacer expands to consume all available
 * space along its stack's main axis by default. Compose's
 * [androidx.compose.foundation.layout.Spacer] has no intrinsic flex — it only
 * fills space when given `Modifier.weight(...)`, which is a `RowScope` /
 * `ColumnScope` member and therefore can only be applied **by the parent
 * container**.
 *
 * Consequently the flex is wired in [VStack] / [HStack]: when a child's `type`
 * is `"Spacer"`, the stack chains `weight(1f)` onto the child modifier in-scope
 * before invoking this builder. This builder just renders the space with
 * whatever modifier it receives — so a Spacer inside a stack fills, and a
 * stack-less Spacer is inert (matching SwiftUI, where a Spacer outside a stack
 * is degenerate).
 *
 * `minLength` (the Apple property) is **not yet ported** — it is a minimum
 * floor on the flexible length and needs the parent axis to map to
 * `widthIn`/`heightIn`. Tracked in `Private/Android_Porting_Notes.md`.
 *
 * Sample JSON: `{ "type": "Spacer" }`
 */
object Spacer : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        LayoutSpacer(modifier = modifier)
    }
}
