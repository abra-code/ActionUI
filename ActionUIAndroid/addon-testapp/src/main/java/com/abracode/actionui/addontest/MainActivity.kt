package com.abracode.actionui.addontest

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIModel

/**
 * ActionUI Add-On Test App - the Android counterpart of Apple's `ActionUIAddOnTestApp`. A minimal selector +
 * detail app (using the core [ActionUI.RenderAsset] entry point) that renders the bundled add-on example
 * documents in `assets/`. Its whole reason to exist is to keep the core `:demoApp` free of any add-on /
 * AsyncImageCache dependency; add-on elements self-register via their ContentProviders once this app links them.
 *
 * Host action handlers for the CachedImage example's value bridge are registered here (the same split the core
 * demo uses for its own elements).
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerCachedImageHandlers()
        enableEdgeToEdge()
        setContent { AddOnTestApp() }
    }

    /**
     * CachedImage.json (id 80): the String value bridge. "cachedimage.read" reads the current image URL;
     * "cachedimage.swap" cycles through DISTINCT seed URLs so every tap visibly swaps - writing the same URL
     * twice is a no-op (the wrapped view keys its load on the URL, SwiftUI parity; the ViewModel value is a
     * structural-equality mutableState, so an identical write triggers no recomposition).
     */
    private fun registerCachedImageHandlers() {
        ActionUIModel.registerActionHandler("cachedimage.read") { _, windowUUID, _, _, _ ->
            val url = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 80)
            Toast.makeText(this, "CachedImage URL: $url", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("cachedimage.swap") { _, windowUUID, _, _, _ ->
            val current = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 80)
            val seeds = listOf("swapped", "mountains", "forest", "harbor")
            val next = seeds[(seeds.indexOfFirst { current?.contains("/seed/$it/") == true } + 1) % seeds.size]
            ActionUIModel.setElementValueFromString(
                windowUUID = windowUUID, viewID = 80,
                value = "https://picsum.photos/seed/$next/1024/768",
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddOnTestApp() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            val context = LocalContext.current
            val documents = remember {
                (context.assets.list("") ?: emptyArray())
                    .filter { it.endsWith(".json", ignoreCase = true) }
                    .sorted()
            }
            var selected by remember { mutableStateOf<String?>(null) }

            when (val current = selected) {
                null -> Scaffold(topBar = { TopAppBar(title = { Text("ActionUI Add-On Test") }) }) { pad ->
                    if (documents.isEmpty()) {
                        Text("No add-on documents in assets.", modifier = Modifier.padding(pad).padding(16.dp))
                    } else {
                        LazyColumn(modifier = Modifier.padding(pad).fillMaxSize()) {
                            items(documents) { name ->
                                ListItem(
                                    headlineContent = { Text(name.removeSuffix(".json")) },
                                    modifier = Modifier.clickable { selected = name },
                                )
                                HorizontalDivider()
                            }
                        }
                    }
                }

                else -> {
                    BackHandler { selected = null }
                    Scaffold(
                        topBar = {
                            TopAppBar(
                                title = { Text(current.removeSuffix(".json")) },
                                navigationIcon = {
                                    IconButton(onClick = { selected = null }) {
                                        Text("<", style = MaterialTheme.typography.headlineSmall)
                                    }
                                },
                            )
                        },
                    ) { pad ->
                        // ActionUI has no ScrollView element yet, so the shell scrolls tall documents.
                        Column(
                            modifier = Modifier
                                .padding(pad)
                                .consumeWindowInsets(pad)
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState()),
                        ) {
                            ActionUI.RenderAsset(assetPath = current, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            }
        }
    }
}
