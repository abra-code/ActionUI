package com.abracode.actionui.Common

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

interface ActionUIViewConstruction {
    @Composable
    fun BuildView(element: ActionUIElement, modifier: Modifier)
}
