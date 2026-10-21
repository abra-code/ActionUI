// Core/Elements/BuiltInElements.swift
/*
 The built-in element types whose spec is portable, keyed by their JSON "type" token. The registry
 reads its spec table from this list; each renderer adds its own table of the same names. The keys
 are the names documents use, so they must not change.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ActionUIRegistry {
    static let builtInSpecs: [(name: String, type: any ActionUIElementSpec.Type)] = [
        ("AsyncImage", AsyncImage.self),
        ("Button", Button.self),
        ("Canvas", Canvas.self),
        ("Capsule", Capsule.self),
        ("Circle", Circle.self),
        ("Color", Color.self),
        ("ColorPicker", ColorPicker.self),
        ("ContentUnavailableView", ContentUnavailableView.self),
        ("ControlGroup", ControlGroup.self),
        ("DatePicker", DatePicker.self),
        ("DisclosureGroup", DisclosureGroup.self),
        ("Divider", Divider.self),
        ("Ellipse", Ellipse.self),
        ("EmptyView", EmptyView.self),
        ("Form", Form.self),
        ("Gauge", Gauge.self),
        ("GeometryReader", GeometryReader.self),
        ("Grid", Grid.self),
        ("Group", Group.self),
        ("GroupBox", GroupBox.self),
        ("HSplitView", HSplitView.self),
        ("HStack", HStack.self),
        ("Image", Image.self),
        ("Label", Label.self),
        ("LabeledContent", LabeledContent.self),
        ("LazyHGrid", LazyHGrid.self),
        ("LazyHStack", LazyHStack.self),
        ("LazyVGrid", LazyVGrid.self),
        ("LazyVStack", LazyVStack.self),
        ("Link", Link.self),
        ("List", List.self),
        ("LoadableView", LoadableView.self),
        ("Map", Map.self),
        ("Menu", Menu.self),
        ("NavigationLink", NavigationLink.self),
        ("NavigationSplitView", NavigationSplitView.self),
        ("NavigationStack", NavigationStack.self),
        ("Picker", Picker.self),
        ("ProgressView", ProgressView.self),
        ("Rectangle", Rectangle.self),
        ("RoundedRectangle", RoundedRectangle.self),
        ("ScrollView", ScrollView.self),
        ("ScrollViewReader", ScrollViewReader.self),
        ("Section", Section.self),
        ("SecureField", SecureField.self),
        ("ShareLink", ShareLink.self),
        ("Slider", Slider.self),
        ("Spacer", Spacer.self),
        ("Stepper", Stepper.self),
        ("Tab", Tab.self),
        ("Table", Table.self),
        ("TabView", TabView.self),
        ("Text", Text.self),
        ("TextEditor", TextEditor.self),
        ("TextField", TextField.self),
        ("Toggle", Toggle.self),
        ("ToolbarItem", ToolbarItem.self),
        ("ToolbarItemGroup", ToolbarItemGroup.self),
        ("VideoPlayer", VideoPlayer.self),
        ("View", View.self),
        ("VSplitView", VSplitView.self),
        ("VStack", VStack.self),
        ("WebView", WebView.self),
        ("ZStack", ZStack.self),
    ]
}
