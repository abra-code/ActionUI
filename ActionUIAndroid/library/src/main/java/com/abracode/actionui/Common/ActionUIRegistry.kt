package com.abracode.actionui.Common

import com.abracode.actionui.Views.Button
import com.abracode.actionui.Views.Capsule
import com.abracode.actionui.Views.Circle
import com.abracode.actionui.Views.Divider
import com.abracode.actionui.Views.Ellipse
import com.abracode.actionui.Views.Group
import com.abracode.actionui.Views.HStack
import com.abracode.actionui.Views.Image
import com.abracode.actionui.Views.LazyHStack
import com.abracode.actionui.Views.LazyVStack
import com.abracode.actionui.Views.Picker
import com.abracode.actionui.Views.ProgressView
import com.abracode.actionui.Views.Rectangle
import com.abracode.actionui.Views.RoundedRectangle
import com.abracode.actionui.Views.SecureField
import com.abracode.actionui.Views.Slider
import com.abracode.actionui.Views.Spacer
import com.abracode.actionui.Views.Stepper
import com.abracode.actionui.Views.Text
import com.abracode.actionui.Views.TextEditor
import com.abracode.actionui.Views.TextField
import com.abracode.actionui.Views.Toggle
import com.abracode.actionui.Views.VStack
import com.abracode.actionui.Views.ZStack

object ActionUIRegistry {
    private val builders = mutableMapOf<String, ActionUIViewConstruction>()

    init {
        register("Text", Text)
        register("VStack", VStack)
        register("HStack", HStack)
        register("ZStack", ZStack)
        register("LazyVStack", LazyVStack)
        register("LazyHStack", LazyHStack)
        register("Button", Button)
        register("Divider", Divider)
        register("Spacer", Spacer)
        register("Image", Image)
        register("Rectangle", Rectangle)
        register("RoundedRectangle", RoundedRectangle)
        register("Capsule", Capsule)
        register("Circle", Circle)
        register("Ellipse", Ellipse)
        register("ProgressView", ProgressView)
        register("TextField", TextField)
        register("SecureField", SecureField)
        register("TextEditor", TextEditor)
        register("Toggle", Toggle)
        register("Slider", Slider)
        register("Picker", Picker)
        register("Stepper", Stepper)
        register("Group", Group)
    }

    fun register(type: String, builder: ActionUIViewConstruction) {
        builders[type] = builder
    }

    fun lookup(type: String): ActionUIViewConstruction? =
        if (type.isEmpty()) null else builders[type]
}
