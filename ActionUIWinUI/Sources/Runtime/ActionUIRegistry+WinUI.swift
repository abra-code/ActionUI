// Sources/Runtime/ActionUIRegistry+WinUI.swift
/*
 The WinUI renderer's half of ActionUIRegistry, as on Linux (ActionUIRegistry+Adwaita.swift): the
 renderer table, keyed like the spec table, and the placeholder for element types that have no
 WinUI renderer yet.
*/

extension ActionUIRegistry {
    // The WinUI renderers of the built-in element types; the others render as the placeholder.
    static let builtInWinUIRenderers: [String: any ActionUIWinUIRenderer.Type] = [
        "Button": Button.self,
        "Capsule": Capsule.self,
        "Circle": Circle.self,
        "Color": Color.self,
        "ContentUnavailableView": ContentUnavailableView.self,
        "DatePicker": DatePicker.self,
        "DisclosureGroup": DisclosureGroup.self,
        "Divider": Divider.self,
        "EmptyView": EmptyView.self,
        "Ellipse": Ellipse.self,
        "Form": Form.self,
        "Gauge": Gauge.self,
        "Grid": Grid.self,
        "GroupBox": GroupBox.self,
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
        "Menu": Menu.self,
        "NavigationLink": NavigationLink.self,
        "NavigationStack": NavigationStack.self,
        "ProgressView": ProgressView.self,
        "Rectangle": Rectangle.self,
        "RoundedRectangle": RoundedRectangle.self,
        "ScrollView": ScrollView.self,
        "Section": Section.self,
        "SecureField": SecureField.self,
        "Slider": Slider.self,
        "Spacer": Spacer.self,
        "Stepper": Stepper.self,
        "TabView": TabView.self,
        "Text": Text.self,
        "TextEditor": TextEditor.self,
        "TextField": TextField.self,
        "Toggle": Toggle.self,
        "VStack": VStack.self,
        "ZStack": ZStack.self,
    ]

    // Static because an extension cannot add stored instance properties; the registry is a single
    // shared instance.
    private static var winUIRenderers: [String: any ActionUIWinUIRenderer.Type] = [:]
    private static var typesReportedMissing: Set<String> = []

    // The WinUI built-ins, after loadBuiltIns has filled `specs`. Core's default hooks stay.
    internal func loadRendererBuiltIns() {
        Self.winUIRenderers = Self.builtInWinUIRenderers
        Self.typesReportedMissing = []
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
