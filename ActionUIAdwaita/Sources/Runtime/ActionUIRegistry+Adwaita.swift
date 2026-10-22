// Sources/Runtime/ActionUIRegistry+Adwaita.swift
/*
 The GTK renderer half of ActionUIRegistry (the SwiftUI half is
 ActionUI/Common/ActionUIRegistry+SwiftUI.swift): the renderer table, keyed like the spec table,
 and the placeholder for element types that have no GTK renderer yet.
*/

extension ActionUIRegistry {
    // The GTK renderers of the built-in element types; the others render as the placeholder.
    static let builtInAdwaitaRenderers: [String: any ActionUIAdwaitaRenderer.Type] = [
        "HStack": HStack.self,
        "LazyHStack": LazyHStack.self,
        "LazyVStack": LazyVStack.self,
        "Spacer": Spacer.self,
        "VStack": VStack.self,
    ]

    // Static because an extension cannot add stored instance properties; the registry is a single
    // shared instance.
    private static var adwaitaRenderers: [String: any ActionUIAdwaitaRenderer.Type] = [:]
    private static var typesReportedMissing: Set<String> = []

    internal var renderers: [String: any ActionUIAdwaitaRenderer.Type] {
        get { Self.adwaitaRenderers }
        set { Self.adwaitaRenderers = newValue }
    }

    // The GTK built-ins, after loadBuiltIns has filled `specs`. Core's default hooks stay.
    internal func loadRendererBuiltIns() {
        renderers = Self.builtInAdwaitaRenderers
        Self.typesReportedMissing = []
    }

    /// The renderer for an element type, or the placeholder (logged once per type) when the type
    /// has none on Linux.
    func adwaitaRenderer(forElementType type: String) -> any ActionUIAdwaitaRenderer.Type {
        if let renderer = renderers[type] {
            return renderer
        }
        if Self.typesReportedMissing.insert(type).inserted {
            logger.log("\(type) is not available on Linux yet; showing a placeholder", .warning)
        }
        return PlaceholderRenderer.self
    }
}
