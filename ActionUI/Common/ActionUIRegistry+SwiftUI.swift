// Common/ActionUIRegistry+SwiftUI.swift
/*
 The SwiftUI renderers of the built-in element types, keyed like ActionUIRegistry.builtInSpecs
 (Core/Elements/BuiltInElements.swift), and the built-in elements that are still Apple-only: their
 spec needs SwiftUI types or helpers, so one type is both their spec and their renderer. Also the
 SwiftUI side of ActionUIRendererHooks.
*/

import SwiftUI

extension ActionUIRegistry {
    static let builtInSwiftUIRenderers: [String: any ActionUISwiftUIRenderer.Type] = [
        "AsyncImage": AsyncImage.self,
        "Button": Button.self,
        "Canvas": Canvas.self,
        "Capsule": Capsule.self,
        "Chart": Chart.self,
        "Circle": Circle.self,
        "Color": Color.self,
        "ColorPicker": ColorPicker.self,
        "ContentUnavailableView": ContentUnavailableView.self,
        "ControlGroup": ControlGroup.self,
        "DatePicker": DatePicker.self,
        "DisclosureGroup": DisclosureGroup.self,
        "Divider": Divider.self,
        "Ellipse": Ellipse.self,
        "EmptyView": EmptyView.self,
        "Form": Form.self,
        "Gauge": Gauge.self,
        "GeometryReader": GeometryReader.self,
        "Grid": Grid.self,
        "Group": Group.self,
        "GroupBox": GroupBox.self,
        "HSplitView": HSplitView.self,
        "HStack": HStack.self,
        "Image": Image.self,
        "Label": Label.self,
        "LabeledContent": LabeledContent.self,
        "LazyHGrid": LazyHGrid.self,
        "LazyHStack": LazyHStack.self,
        "LazyVGrid": LazyVGrid.self,
        "LazyVStack": LazyVStack.self,
        "Link": Link.self,
        "List": List.self,
        "LoadableView": LoadableView.self,
        "Map": Map.self,
        "Menu": Menu.self,
        "NavigationLink": NavigationLink.self,
        "NavigationSplitView": NavigationSplitView.self,
        "NavigationStack": NavigationStack.self,
        "Picker": Picker.self,
        "ProgressView": ProgressView.self,
        "Rectangle": Rectangle.self,
        "RoundedRectangle": RoundedRectangle.self,
        "ScrollView": ScrollView.self,
        "ScrollViewReader": ScrollViewReader.self,
        "Section": Section.self,
        "SecureField": SecureField.self,
        "ShareLink": ShareLink.self,
        "Slider": Slider.self,
        "Spacer": Spacer.self,
        "Stepper": Stepper.self,
        "Tab": Tab.self,
        "Table": Table.self,
        "TabView": TabView.self,
        "Text": Text.self,
        "TextEditor": TextEditor.self,
        "TextField": TextField.self,
        "Toggle": Toggle.self,
        "ToolbarItem": ToolbarItem.self,
        "ToolbarItemGroup": ToolbarItemGroup.self,
        "VideoPlayer": VideoPlayer.self,
        "View": View.self,
        "VSplitView": VSplitView.self,
        "VStack": VStack.self,
        "WebView": WebView.self,
        "ZStack": ZStack.self,
    ]

    static let appleOnlySpecs: [(name: String, type: any ActionUIElementSpec.Type)] = [
        ("Chart", Chart.self),
        ("Color", Color.self),
        ("ColorPicker", ColorPicker.self),
    ]

    // ActionUIRendererHooks.structuralMutation for SwiftUI: an animated insert or removal runs
    // inside withAnimation, so the element's .transition() plays.
    static func swiftUIStructuralMutation(animated: Bool, body: () -> Void) {
        if animated {
            withAnimation { body() }
        } else {
            body()
        }
    }
}
