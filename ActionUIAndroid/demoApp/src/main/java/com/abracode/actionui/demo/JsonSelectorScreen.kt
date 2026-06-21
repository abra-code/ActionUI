package com.abracode.actionui.demo

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.ActionUI

/**
 * Native (Compose) JSON picker for the demo app - the Android counterpart of the
 * Swift test app's `JSONSelectorView` (`ActionUISwiftTestApp.swift`). The picker
 * itself is plain Compose shell code around the renderer (not an ActionUI
 * document); the picker -> detail routing is a Navigation Compose `NavHost`
 * (see `DemoApp`) so a `NavigationStack` inside a rendered document nests under
 * the system back button.
 *
 * Flow: [JsonSelectorScreen] lists the bundled `.json` example files in
 * `assets/`; tapping one routes to [ExampleDetailScreen], which renders that
 * document with [ActionUI.RenderAsset] inside a scroll container (the demo shell
 * provides scrolling for documents taller than the viewport) and offers a top-bar
 * back affordance; system back is owned by the host NavHost.
 *
 * The list also carries one synthetic entry, [RENDER_SOURCE_DEMO_LABEL], that is
 * not a bundled file: it renders a remote document as the window *root* via
 * [ActionUI.RenderSource] (the Android counterpart of Apple's `LoadableWindowGroup`
 * / `isContentView == true`), to demonstrate root-replacement loading.
 */

/**
 * Synthetic selector entry (not an asset file): renders a remote document as the
 * window root via [ActionUI.RenderSource], demonstrating async root replacement.
 */
const val RENDER_SOURCE_DEMO_LABEL: String = "RenderSource (remote root)"
private const val RENDER_SOURCE_DEMO_URL: String = "https://abracode.com/ActionUI/HelloWorld.json"

/** Lists the bundled example documents: top-level `.json` files in `assets/`, sorted. */
fun listJsonAssets(context: Context): List<String> =
    (context.assets.list("") ?: emptyArray())
        .filter { it.endsWith(".json", ignoreCase = true) }
        .sorted()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JsonSelectorScreen(
    files: List<String>,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text("ActionUI - JSON Selector") }) },
    ) { innerPadding ->
        if (files.isEmpty()) {
            Text(
                text = "No JSON files found in assets.",
                modifier = Modifier.padding(innerPadding).padding(16.dp),
            )
        } else {
            LazyColumn(modifier = Modifier.padding(innerPadding).fillMaxSize()) {
                items(files) { name ->
                    ListItem(
                        headlineContent = { Text(name.removeSuffix(".json")) },
                        modifier = Modifier.clickable { onSelect(name) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExampleDetailScreen(
    assetPath: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Back - both the system gesture/button and the top-bar arrow - is routed
    // through the OnBackPressedDispatcher (DemoApp hosts the picker/detail flow in a
    // NavHost). That way a NavigationStack inside the rendered document pops its own
    // push levels first, and only the detail route's final back returns to the
    // picker. The arrow MUST dispatch rather than pop the host controller directly:
    // a direct pop (or a BackHandler here, which registers in a DisposableEffect
    // after the document's NavHost registers during composition) would skip the
    // nested NavHost and jump straight to the picker from any depth.
    val backDispatcher = LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(assetPath.removeSuffix(".json")) },
                navigationIcon = {
                    IconButton(onClick = { backDispatcher?.onBackPressed() ?: onBack() }) {
                        // Avoid a material-icons dependency for one glyph.
                        Text("<", style = MaterialTheme.typography.headlineSmall)
                    }
                },
            )
        },
    ) { innerPadding ->
        // ActionUI has no ScrollView element yet, so the native shell provides
        // scrolling for documents taller than the viewport.
        Column(
            modifier = Modifier
                .padding(innerPadding)
                // Consume the insets the Scaffold already padded for, so a nested insets-aware
                // component inside the document (a safeAreaInset bar's windowInsetsPadding) does not
                // double-count the system bars and reserve a spurious second gap.
                .consumeWindowInsets(innerPadding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            if (assetPath == RENDER_SOURCE_DEMO_LABEL) {
                // Root-replacement loadable: fetch a remote document and render it
                // as the window root (spinner while loading, error text on failure).
                ActionUI.RenderSource(source = RENDER_SOURCE_DEMO_URL, modifier = Modifier.fillMaxWidth())
            } else {
                ActionUI.RenderAsset(assetPath = assetPath, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

/**
 * Renders a document edge-to-edge as the window root - no Scaffold, top bar, or outer scroll - so its
 * ignoresSafeArea / safeAreaInset reach the real screen edges (status bar / camera cutout / gesture nav),
 * which the Scaffold-framed [ExampleDetailScreen] cannot show. System back returns to the picker.
 */
@Composable
fun ExampleFullscreenScreen(
    assetPath: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BackHandler { onBack() }
    Box(modifier.fillMaxSize()) {
        ActionUI.RenderAsset(assetPath = assetPath, modifier = Modifier.fillMaxSize())
    }
}
