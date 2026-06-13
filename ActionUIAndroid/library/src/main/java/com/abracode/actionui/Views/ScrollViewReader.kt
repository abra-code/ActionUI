package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.LocalScrollViewReaderState
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.ScrollViewReaderState
import com.abracode.actionui.Helpers.resolveScrollAnchor
import com.abracode.actionui.Helpers.resolveScrollTarget

/**
 * Programmatic-scrolling wrapper around a single scrollable child. Mirror of
 * the Apple `ScrollViewReader` element (`ActionUI/Views/ScrollViewReader.swift`),
 * which wraps `SwiftUI.ScrollViewReader`. Like [ScrollView] it reads the
 * single-child `content` named container; when no `content` is present it
 * renders nothing.
 *
 * **Supported properties.**
 *   * `scrollTo` - the id of the element to scroll to. Must be an Int
 *     (warn-and-ignore otherwise, the Apple validator's rule). Honored on
 *     first composition when authored in the JSON, and re-honored whenever
 *     the host rewrites it with `ActionUIModel.setElementProperty` - the
 *     Android version of calling `proxy.scrollTo` at runtime. Re-setting the
 *     *same* id scrolls again (the element's `mutationToken` keys the
 *     effect), so "bring row N back" works after the user scrolls away.
 *   * `anchor` - where the target lands in the viewport: `"top"`,
 *     `"center"` (default), or `"bottom"`.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 *
 * The scroll machinery lives in `Helpers/ScrollReaderHelper.kt`: the reader
 * provides a [ScrollViewReaderState] through [LocalScrollViewReaderState],
 * the scroll containers in the subtree enroll themselves (`ScrollView` with
 * its `ScrollState`s; `LazyVStack` / `LazyHStack` / `List` children mode with
 * their `LazyListState` and an id-to-row resolver), and every element with a
 * positive id registers its coordinates at the shared build entry point. See
 * that file for dispatch order, anchor semantics, and the documented
 * divergences (template/homogeneous rows and the lazy grids are not
 * addressable).
 */
object ScrollViewReader : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val content = element.content ?: return
        val builder = ActionUIRegistry.lookup(content.type) ?: return

        val state = remember { ScrollViewReaderState() }
        Box(modifier) {
            CompositionLocalProvider(LocalScrollViewReaderState provides state) {
                ProvideTextStyleEnvironment(content.properties, logger) {
                    builder.BuildViewWithModifiers(content, Modifier)
                }
            }
        }

        // BuildViewWithModifiers already merged the host's property overrides
        // into `element`, so a setElementProperty("scrollTo", ...) lands here
        // through ordinary recomposition. Reading mutationToken keys the
        // effect to *every* host write, so re-sending the same id re-scrolls.
        val scrollTarget = resolveScrollTarget(element.properties, logger)
        val anchor = resolveScrollAnchor(element.properties, logger)
        val mutationToken = LocalWindowModel.current?.viewModels?.get(element.id)?.mutationToken ?: 0
        if (scrollTarget != null) {
            LaunchedEffect(scrollTarget, anchor, mutationToken) {
                state.scrollTo(scrollTarget, anchor, logger)
            }
        }
    }
}
