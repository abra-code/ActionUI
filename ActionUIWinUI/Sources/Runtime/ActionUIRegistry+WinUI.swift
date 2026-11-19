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
        "Divider": Divider.self,
        "Ellipse": Ellipse.self,
        "GroupBox": GroupBox.self,
        "HStack": HStack.self,
        "Image": Image.self,
        "Label": Label.self,
        "Picker": Picker.self,
        "LabeledContent": LabeledContent.self,
        "List": List.self,
        "Rectangle": Rectangle.self,
        "RoundedRectangle": RoundedRectangle.self,
        "ScrollView": ScrollView.self,
        "Spacer": Spacer.self,
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
