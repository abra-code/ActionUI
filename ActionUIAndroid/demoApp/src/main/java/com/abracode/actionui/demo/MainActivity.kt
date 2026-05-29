package com.abracode.actionui.demo

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.demo.ui.theme.ActionUIAndroidTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Demonstrate client-side action registration, mirroring how an Apple
        // host wires up ActionUIModel.shared handlers. The specific handler
        // fires for "button.tap"; everything else (e.g. "button.delete") falls
        // through to the default handler.
        ActionUIModel.registerActionHandler("button.tap") { actionID, _, viewID, _, _ ->
            Toast.makeText(this, "Handled '$actionID' (viewID=$viewID)", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.setDefaultActionHandler { actionID, _, viewID, _, _ ->
            Toast.makeText(this, "Default handler: '$actionID' (viewID=$viewID)", Toast.LENGTH_SHORT).show()
        }

        enableEdgeToEdge()
        setContent {
            ActionUIAndroidTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    ActionUIScreen(modifier = Modifier.padding(innerPadding))
                }
            }
        }
    }
}

@Composable
fun ActionUIScreen(modifier: Modifier = Modifier) {
    ActionUI.RenderAsset(assetPath = "HelloWorld.json", modifier = modifier)
}
