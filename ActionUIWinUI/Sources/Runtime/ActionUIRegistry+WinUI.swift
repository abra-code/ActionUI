// Sources/Runtime/ActionUIRegistry+WinUI.swift
/*
 The WinUI renderer's half of ActionUIRegistry, as on Linux (ActionUIRegistry+Adwaita.swift): the
 renderer table, keyed like the spec table, and the placeholder for element types that have no
 WinUI renderer yet.
*/

import CLinkedAddOns

extension ActionUIRegistry {
    // The WinUI renderers of the built-in element types; the others render as the placeholder.
    static let builtInWinUIRenderers: [String: any ActionUIWinUIRenderer.Type] = [
        "AsyncImage": AsyncImage.self,
        "Button": Button.self,
        "Canvas": Canvas.self,
        "Chart": Chart.self,
        "Capsule": Capsule.self,
        "Circle": Circle.self,
        "Color": Color.self,
        "ColorPicker": ColorPicker.self,
        "ContentUnavailableView": ContentUnavailableView.self,
        "ControlGroup": ControlGroup.self,
        "DatePicker": DatePicker.self,
        "DisclosureGroup": DisclosureGroup.self,
        "Divider": Divider.self,
        "EmptyView": EmptyView.self,
        "Ellipse": Ellipse.self,
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
        "LazyHGrid": LazyHGrid.self,
        "LazyHStack": LazyHStack.self,
        "LazyVGrid": LazyVGrid.self,
        "LazyVStack": LazyVStack.self,
        "Link": Link.self,
        "Picker": Picker.self,
        "LabeledContent": LabeledContent.self,
        "List": List.self,
        "LoadableView": LoadableView.self,
        "Map": Map.self,
        "Menu": Menu.self,
        "NavigationLink": NavigationLink.self,
        "NavigationSplitView": NavigationSplitView.self,
        "NavigationStack": NavigationStack.self,
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
        "TabView": TabView.self,
        "Table": Table.self,
        "Text": Text.self,
        "TextEditor": TextEditor.self,
        "TextField": TextField.self,
        "Toggle": Toggle.self,
        "VSplitView": VSplitView.self,
        "VideoPlayer": VideoPlayer.self,
        "VStack": VStack.self,
        "WebView": WebView.self,
        "ZStack": ZStack.self,
    ]

    // Static because an extension cannot add stored instance properties; the registry is a single
    // shared instance.
    private static var winUIRenderers: [String: any ActionUIWinUIRenderer.Type] = [:]
    private static var typesReportedMissing: Set<String> = []

    // The WinUI built-ins, after loadBuiltIns has filled `specs`. Core's other default hooks stay.
    internal func loadRendererBuiltIns() {
        Self.winUIRenderers = Self.builtInWinUIRenderers
        Self.typesReportedMissing = []
        // The add-ons linked into the same program or library, registered before the first UI
        // description loads (ActionUIModel), as on Linux.
        ActionUIRendererHooks.registerLinkedAddOns = actionUIRegisterLinkedAddOns
        // The app's own resources, whose ActionUI JSON is trusted: the host's folder, else the
        // program's.
        ActionUIRendererHooks.resourceFolders = LinkTrust.resourceFolders
        // Dates in the user's time zone, which FoundationEssentials alone does not know (Windows' zone data).
        LocalTime.offset = SystemTimeOffset.seconds(at:)
    }

    /// Binds `renderer` to an element type (register(_:as:), for an add-on's element).
    func setWinUIRenderer(_ renderer: any ActionUIWinUIRenderer.Type, forElementType type: String) {
        Self.winUIRenderers[type] = renderer
    }

    /// The renderer for an element type, or the placeholder (logged once per type) when the type
    /// has none on Windows.
    func winUIRenderer(forElementType type: String) -> any ActionUIWinUIRenderer.Type {
        if let renderer = Self.winUIRenderers[type] {
            return renderer
        }
        if Self.typesReportedMissing.insert(type).inserted {
            logger.log("\(type) is not available on Windows yet; showing a placeholder", .warning)
        }
        return PlaceholderRenderer.self
    }
}
