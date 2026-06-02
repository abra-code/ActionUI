package com.abracode.actionui.Common

import com.abracode.actionui.Views.Button
import com.abracode.actionui.Views.Divider
import com.abracode.actionui.Views.HStack
import com.abracode.actionui.Views.Image
import com.abracode.actionui.Views.Spacer
import com.abracode.actionui.Views.Text
import com.abracode.actionui.Views.VStack

object ActionUIRegistry {
    private val builders = mutableMapOf<String, ActionUIViewConstruction>()

    init {
        register("Text", Text)
        register("VStack", VStack)
        register("HStack", HStack)
        register("Button", Button)
        register("Divider", Divider)
        register("Spacer", Spacer)
        register("Image", Image)
    }

    fun register(type: String, builder: ActionUIViewConstruction) {
        builders[type] = builder
    }

    fun lookup(type: String): ActionUIViewConstruction? =
        if (type.isEmpty()) null else builders[type]
}
