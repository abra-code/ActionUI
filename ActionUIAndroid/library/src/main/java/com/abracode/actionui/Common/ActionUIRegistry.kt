package com.abracode.actionui.Common

import com.abracode.actionui.Views.Button
import com.abracode.actionui.Views.Capsule
import com.abracode.actionui.Views.Circle
import com.abracode.actionui.Views.ColorPicker
import com.abracode.actionui.Views.ContentUnavailableView
import com.abracode.actionui.Views.DatePicker
import com.abracode.actionui.Views.DisclosureGroup
import com.abracode.actionui.Views.Divider
import com.abracode.actionui.Views.Ellipse
import com.abracode.actionui.Views.EmptyView
import com.abracode.actionui.Views.Form
import com.abracode.actionui.Views.Group
import com.abracode.actionui.Views.GroupBox
import com.abracode.actionui.Views.HStack
import com.abracode.actionui.Views.Image
import com.abracode.actionui.Views.Label
import com.abracode.actionui.Views.LabeledContent
import com.abracode.actionui.Views.LazyHStack
import com.abracode.actionui.Views.LazyVStack
import com.abracode.actionui.Views.Link
import com.abracode.actionui.Views.Menu
import com.abracode.actionui.Views.ListView
import com.abracode.actionui.Views.NavigationLink
import com.abracode.actionui.Views.NavigationSplitView
import com.abracode.actionui.Views.NavigationStack
import com.abracode.actionui.Views.Picker
import com.abracode.actionui.Views.ProgressView
import com.abracode.actionui.Views.Rectangle
import com.abracode.actionui.Views.RoundedRectangle
import com.abracode.actionui.Views.ScrollView
import com.abracode.actionui.Views.Section
import com.abracode.actionui.Views.SecureField
import com.abracode.actionui.Views.ShareLink
import com.abracode.actionui.Views.Slider
import com.abracode.actionui.Views.Spacer
import com.abracode.actionui.Views.Stepper
import com.abracode.actionui.Views.Tab
import com.abracode.actionui.Views.TabView
import com.abracode.actionui.Views.Table
import com.abracode.actionui.Views.Text
import com.abracode.actionui.Views.TextEditor
import com.abracode.actionui.Views.ToolbarItem
import com.abracode.actionui.Views.ToolbarItemGroup
import com.abracode.actionui.Views.TextField
import com.abracode.actionui.Views.Toggle
import com.abracode.actionui.Views.VStack
import com.abracode.actionui.Views.ZStack

object ActionUIRegistry {
    private val builders = mutableMapOf<String, ActionUIViewConstruction>()

    init {
        register("Text", Text)
        register("Label", Label)
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
        register("ScrollView", ScrollView)
        register("GroupBox", GroupBox)
        register("LabeledContent", LabeledContent)
        register("DisclosureGroup", DisclosureGroup)
        register("Link", Link)
        register("ShareLink", ShareLink)
        register("ContentUnavailableView", ContentUnavailableView)
        register("EmptyView", EmptyView)
        register("List", ListView)
        register("Section", Section)
        register("Form", Form)
        register("Table", Table)
        register("DatePicker", DatePicker)
        register("ColorPicker", ColorPicker)
        register("NavigationStack", NavigationStack)
        register("NavigationLink", NavigationLink)
        register("NavigationSplitView", NavigationSplitView)
        register("TabView", TabView)
        register("Tab", Tab)
        register("Menu", Menu)
        register("ToolbarItem", ToolbarItem)
        register("ToolbarItemGroup", ToolbarItemGroup)
    }

    fun register(type: String, builder: ActionUIViewConstruction) {
        builders[type] = builder
    }

    fun lookup(type: String): ActionUIViewConstruction? =
        if (type.isEmpty()) null else builders[type]
}
