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

// The SwiftUI half of the registry: the renderer table, add-on registration, and building and
// modifying views. The spec table and the document-load queries are in Core/Common/ActionUIRegistry.swift.
extension ActionUIRegistry {
    // Each element type's SwiftUI renderer, keyed like `specs`. Static because an extension
    // cannot add stored instance properties; the registry is a single shared instance.
    private static var swiftUIRenderers: [String: any ActionUISwiftUIRenderer.Type] = [:]

    internal var renderers: [String: any ActionUISwiftUIRenderer.Type] {
        get { Self.swiftUIRenderers }
        set { Self.swiftUIRenderers = newValue }
    }

    // The SwiftUI built-ins, after loadBuiltIns has filled `specs` with the portable ones: the
    // Apple-only specs, the renderer table, and the SwiftUI hooks.
    internal func loadRendererBuiltIns() {
        specs.merge(Self.appleOnlySpecs.map { ($0.name, $0.type) }) { _, _ in
            preconditionFailure("An Apple-only element type is also a portable built-in")
        }
        renderers = Self.builtInSwiftUIRenderers
        ActionUIRendererHooks.structuralMutation = Self.swiftUIStructuralMutation
        ActionUIRendererHooks.markdown = { (try? AttributedString(markdown: $0)) ?? AttributedString($0) }
        ActionUIRendererHooks.colorHex = { ColorHelper.colorToHex(ColorHelper.color(for: $0)) }
        ActionUIRendererHooks.hostValue = { value in
            (value as? SwiftUI.Color).flatMap(ColorHelper.hostSpec(for:)) ?? value
        }
        Text.parseStringValue = Text.swiftUIParseStringValue
        Text.serializeValueToString = Text.swiftUISerializeValueToString
        TextEditor.parseStringValue = TextEditor.swiftUIParseStringValue
        TextEditor.serializeValueToString = TextEditor.swiftUISerializeValueToString
    }

    /// Registers an external, add-on view-construction type so its `type` token can be used in
    /// ActionUI JSON exactly like a built-in element. Intended for optional plug-in libraries that
    /// link against ActionUI (for example a custom `Chat` element) and self-register at launch.
    ///
    /// Apple platforms have no guaranteed pre-`main` discovery hook for a statically linked Swift
    /// type (unlike the ActionUIAndroid map providers, where a manifest-declared ContentProvider
    /// self-registers purely on link), so an add-on exposes a tiny `register()` entry point that the
    /// host app calls once at startup, before any window referencing the type is built. Registration
    /// is idempotent; a later call for the same token replaces the earlier construction type.
    ///
    /// - Parameters:
    ///   - type: a type conforming to ``ActionUIViewConstruction``.
    ///   - typeName: the JSON `type` token to bind. Defaults to the Swift type's own name
    ///     (e.g. `Chat` -> "Chat"), matching how built-in elements are keyed.
    public func register(_ type: any ActionUIViewConstruction.Type, as typeName: String? = nil) {
        let key = typeName ?? String(describing: type)
        specs[key] = type
        renderers[key] = type
        logger.log("Registered custom view type: \(key)", .verbose)
    }

    // Builds a SwiftUI view for an element from its current properties, leaving value and
    // view-specific state to buildView
    func buildView(for element: any ActionUIElementBase, model: ViewModel, windowUUID: String, properties: [String: Any]) -> any SwiftUI.View {
        // Merge any runtime structural mutations (insertElement / removeElement) before
        // passing the element to view-specific construction. The view-type closures still
        // read element.subviews[container]; the merged element makes those reads see the live state.
        let effectiveElement = applyDynamicSubviews(to: element, model: model)

        if let constructionType = renderers[effectiveElement.type] {
            return constructionType.buildView(effectiveElement, model, windowUUID, properties, logger)
        }
        logger.log("No construction type found for element ID \(effectiveElement.id) of type '\(effectiveElement.type)' in window \(windowUUID), returning EmptyView", .warning)

        return SwiftUI.EmptyView()
    }


    // Applies modifiers to a view, using a ViewModel for dynamic updates
    // Design decision: Uses the current properties in model to support dynamic property changes (e.g., disabled) via setProperty, ensuring SwiftUI refreshes
    // Applies baseline View modifiers first, then view-specific modifiers, per the guide's modifier separation principle
    func applyViewModifiers(to view: any SwiftUI.View, properties: [String: Any], element: any ActionUIElementBase, model: ViewModel, windowUUID: String) -> AnyView {
        
        var modifiedView = view
        // First apply specialized view modifications if available (View.applyModifiers can erase specific view type)
        if let constructionType = renderers[element.type] {
            modifiedView = constructionType.applyModifiers(modifiedView, element, windowUUID, properties, logger)
        } else {
            logger.log("No modifier registration found for element ID \(element.id) of type '\(element.type)', applying base modifiers only", .warning)
        }
        
        // Apply base View modifications dynamically
        // Design decision: Delegates baseline modifiers (e.g., padding, disabled, hidden) to View.applyModifiers to centralize shared logic
        modifiedView = View.applyModifiers(modifiedView, element, windowUUID, baseModifierProperties(properties, forElementType: element.type), logger)

        // Whole-container tap (Helpers/ContainerAction+SwiftUI.swift): a VStack/HStack/ZStack
        // carrying an actionID becomes ONE tap target. Applied here, last, because the target
        // has to cover the container's FINAL box - the frame, padding and background that
        // View.applyModifiers just added. Applied inside buildView instead, the shape sizes to
        // the stack's intrinsic content, and a padded full-width tinted row is dead everywhere
        // its children do not happen to draw. A no-op for every other element type, and for a
        // tappable container that declares no actionID.
        modifiedView = ContainerAction.apply(
            modifiedView, element: element, model: model, windowUUID: windowUUID, properties: properties
        )

        return AnyView(modifiedView)
    }
}
