package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.stringProperty

/**
 * Titled, visually grouped container around a set of children. Mirror of the
 * Apple `GroupBox` element (`ActionUI/Views/GroupBox.swift`), which wraps
 * `SwiftUI.GroupBox`.
 *
 * Compose has no `GroupBox`, so it is rendered as a Material3 [OutlinedCard]: an
 * optional `title` label at the top, then the `children` laid out vertically -
 * the default SwiftUI `GroupBoxStyle` shape (bordered box, label above content).
 *
 * **Supported properties.**
 *   * `title` - optional String shown above the content; absent / non-string
 *     omits the label (matching the Apple validator's warn-and-nil).
 *   * `children` - the grouped views, laid out in a [Column]; each gets the
 *     [androidx.compose.foundation.layout.ColumnScope] child modifier (so
 *     per-child `weight` / `align` work, as in [VStack]).
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 *
 * **Deferred vs. Apple.** The data-driven `template` mode needs the row/state
 * layer that has not landed yet; only static `children` are rendered. See
 * `Private/Android_Porting_Notes.md`.
 */
object GroupBox : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val title = element.properties?.stringProperty("title")

        OutlinedCard(modifier = modifier) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (!title.isNullOrEmpty()) {
                    M3Text(title, style = MaterialTheme.typography.titleSmall)
                }
                element.children.orEmpty().forEach { child ->
                    val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                    ProvideTextStyleEnvironment(child.properties, logger) {
                        builder.BuildView(child, buildChildModifier(child.properties, logger))
                    }
                }
            }
        }
    }
}
