package com.abracode.actionui.Common

import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf

/**
 * The layout axis of the nearest enclosing stack, exposed to descendant
 * elements that must adapt to their container's orientation.
 *
 * SwiftUI infers some elements' orientation from context — most notably
 * `Divider`, which renders as a horizontal rule inside a `VStack` and a
 * vertical rule inside an `HStack`. Compose has no such inference: it ships
 * distinct `HorizontalDivider` / `VerticalDivider` composables, and a child has
 * no built-in way to learn whether it sits in a `Row` or a `Column`. This
 * CompositionLocal carries that fact down the tree so the orientation-sensitive
 * builders can mirror SwiftUI's automatic behavior.
 *
 * [VStack] provides [Vertical]; [HStack] provides [Horizontal]. The root
 * default is [Vertical] so a stack-less top-level `Divider` renders as a
 * horizontal rule, matching SwiftUI's default.
 */
enum class StackAxis {
    /** A vertical stack (Column / VStack): children are laid out top-to-bottom. */
    Vertical,
    /** A horizontal stack (Row / HStack): children are laid out start-to-end. */
    Horizontal
}

/**
 * CompositionLocal carrying the active [StackAxis]. Defaults to
 * [StackAxis.Vertical] (the SwiftUI default for a divider with no enclosing
 * stack). Uses [compositionLocalOf] — not the `static` variant — because the
 * value legitimately changes at every nested stack boundary, so subtrees that
 * read it must recompose when it does.
 */
val LocalStackAxis: ProvidableCompositionLocal<StackAxis> =
    compositionLocalOf { StackAxis.Vertical }
