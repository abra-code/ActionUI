// Sources/Styling/MaterialSymbols.swift
/*
 The icons that stand in for SF Symbols, which may not be shipped off Apple platforms: Material
 Symbols Rounded glyphs drawn as symbolic SVG icons at build time (the SymbolIcons build plugin),
 one per distinct glyph, fill and weight among the rows of ActionUIAndroid's sf_to_material.map,
 the SF -> Material map Android and Web use too. Each row's fill and weight are kept: the map's weights match each glyph's strokes to
 SF Symbols at regular weight.

 The icons and the map are one GResource compiled into the library (materialSymbolsResourceBase64,
 the plugin's output). It is registered once per process and added to the default display's icon
 theme, where GTK finds the icons by name and recolors them with the text color like any symbolic
 icon. An icon's name comes from its map row, as the generator (ActionUIAdwaita/SymbolIcons) names
 it: actionui-material-<hex codepoint>-f<0|1>-w<weight>-symbolic.
*/

import CAdwaita

@MainActor
enum MaterialSymbols {
    /// Where the resource's icons and map are.
    static let resourcePath = "/com/abracode/actionui/symbols"

    private static var registered = false
    private static var registrationFailed = false
    private static var addedToIconTheme = false
    private static var table: [String: String]?

    /// The icon theme name for an SF Symbol name, nil when the map has no row for it. Adds the
    /// icons to the icon theme first.
    static func iconName(_ symbol: String) -> String? {
        addToIconTheme()
        return names[symbol]
    }

    /// SF Symbol name -> icon theme name, for every row of the map (empty when the resource
    /// cannot be read, which is logged).
    static var names: [String: String] {
        if let table {
            return table
        }
        let parsed = register() ? readMap() : [:]
        table = parsed
        return parsed
    }

    /// Puts the icons on the default display's icon theme, once.
    static func addToIconTheme() {
        guard !addedToIconTheme, register(), let display = gdk_display_get_default() else { return }
        addedToIconTheme = true
        gtk_icon_theme_add_resource_path(gtk_icon_theme_get_for_display(display), resourcePath)
    }

    /// Registers the compiled-in resource with GLib, once; false (logged once) when it cannot be.
    @discardableResult
    static func register() -> Bool {
        if registered || registrationFailed {
            return registered
        }
        var length: gsize = 0
        guard let data = g_base64_decode(materialSymbolsResourceBase64, &length), length > 0 else {
            ActionUIModel.shared.logger.log("The symbol icons compiled into the library cannot be read; SF Symbols show image-missing", .error)
            registrationFailed = true
            return false
        }
        // The decoded block (from g_malloc, so aligned as GResource needs) belongs to the bytes,
        // and the resource is kept for the life of the process.
        let bytes = g_bytes_new_take(data, length)
        defer { g_bytes_unref(bytes) }
        var error: UnsafeMutablePointer<GError>?
        guard let resource = g_resource_new_from_data(bytes, &error) else {
            let message = error.flatMap { swiftString($0.pointee.message) } ?? "unknown error"
            if let error { g_error_free(error) }
            ActionUIModel.shared.logger.log("The symbol icons compiled into the library are not a resource (\(message)); SF Symbols show image-missing", .error)
            registrationFailed = true
            return false
        }
        g_resources_register(resource)
        registered = true
        return true
    }

    /// The map's rows as icon names, from the registered resource.
    private static func readMap() -> [String: String] {
        var error: UnsafeMutablePointer<GError>?
        guard let bytes = g_resources_lookup_data(resourcePath + "/sf_to_material.map", G_RESOURCE_LOOKUP_FLAGS_NONE, &error) else {
            let message = error.flatMap { swiftString($0.pointee.message) } ?? "unknown error"
            if let error { g_error_free(error) }
            ActionUIModel.shared.logger.log("The symbol map is missing from the library's resource (\(message)); SF Symbols show image-missing", .error)
            return [:]
        }
        defer { g_bytes_unref(bytes) }
        var size: gsize = 0
        guard let start = g_bytes_get_data(bytes, &size), size > 0 else { return [:] }
        let text = String(decoding: UnsafeRawBufferPointer(start: start, count: Int(size)), as: UTF8.self)
        return parseMap(text)
    }

    /// Icon names for the rows of a map's text: `<sf_name> <hex codepoint> [1: fill] [100..700:
    /// weight]`, no fill meaning 0 and no weight 400; comment lines start with "#". Malformed rows
    /// are skipped (the generator refuses them, so the build would have failed).
    static func parseMap(_ text: String) -> [String: String] {
        var names: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
            guard parts.count >= 2, let codepoint = UInt32(parts[1], radix: 16) else { continue }
            var fill = 0
            var weight = 400
            for token in parts.dropFirst(2) {
                guard let value = Int(token) else { continue }
                if value == 1 {
                    fill = 1
                } else if (100...700).contains(value) {
                    weight = value
                }
            }
            names[String(parts[0])] = "actionui-material-\(String(codepoint, radix: 16))-f\(fill)-w\(weight)-symbolic"
        }
        return names
    }
}
