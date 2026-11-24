// Sources/Styling/SymbolIcons.swift
/*
 The icons that stand in for SF Symbols, which may not be shipped off Apple platforms, drawn as
 symbolic SVG icons before the build (Scripts/prepare-linux-symbols.sh): Material Symbols Rounded
 glyphs, one per distinct glyph, fill and weight among the rows of ActionUIAndroid's
 sf_to_material.map, the SF -> Material map Android and Web use too, each row's fill and weight
 kept (the map's weights match each glyph's strokes to SF Symbols at regular weight); and, for the
 SF names that map has no row for, the Fluent System Icons glyph of Tools/fluent_symbols'
 sf_to_fluent.map, as on Windows, the regular ones' strokes thickened to Material's.

 The icons and a table of SF names and icon names are one GResource in a section of whatever links
 ActionUI (CSymbolResource), read in place. It is registered once per process and added to the
 default display's icon theme, where GTK finds the icons by name and recolors them with the text
 color like any symbolic icon. The generator (Tools/material_symbols/generate-symbol-icons.c) names
 the icons and writes the table, so the rules for which icon a name gets live there alone.
*/

import CAdwaita
import CSymbolResource

@MainActor
enum SymbolIcons {
    /// Where the resource's icons and table are.
    static let resourcePath = "/com/abracode/actionui/symbols"

    private static var registered = false
    private static var registrationFailed = false
    private static var addedToIconTheme = false
    private static var table: [String: String]?

    /// The icon theme name for an SF Symbol name, nil when the table has no row for it. Adds the
    /// icons to the icon theme first.
    static func iconName(_ symbol: String) -> String? {
        addToIconTheme()
        return names[symbol]
    }

    /// SF Symbol name -> icon theme name, for every row of the table (empty when the resource
    /// cannot be read, which is logged).
    static var names: [String: String] {
        if let table {
            return table
        }
        let parsed = register() ? readTable() : [:]
        table = parsed
        return parsed
    }

    /// Puts the icons on the default display's icon theme, once.
    static func addToIconTheme() {
        guard !addedToIconTheme, register(), let display = gdk_display_get_default() else { return }
        addedToIconTheme = true
        gtk_icon_theme_add_resource_path(gtk_icon_theme_get_for_display(display), resourcePath)
    }

    /// Registers the compiled-in resource with GLib, once; false (logged once) when ActionUI was
    /// built without it.
    @discardableResult
    static func register() -> Bool {
        if registered || registrationFailed {
            return registered
        }
        guard actionui_symbol_resource_register() else {
            ActionUIModel.shared.logger.log("ActionUI was built without its symbol icons (run Scripts/prepare-linux-symbols.sh before swift build); SF Symbols show image-missing", .error)
            registrationFailed = true
            return false
        }
        registered = true
        return true
    }

    /// The table's rows, from the registered resource.
    private static func readTable() -> [String: String] {
        var error: UnsafeMutablePointer<GError>?
        guard let bytes = g_resources_lookup_data(resourcePath + "/symbols.map", GResourceLookupFlags(rawValue: 0), &error) else {
            let message = error.flatMap { swiftString($0.pointee.message) } ?? "unknown error"
            if let error { g_error_free(error) }
            ActionUIModel.shared.logger.log("The symbol table is missing from the library's resource (\(message)); SF Symbols show image-missing", .error)
            return [:]
        }
        defer { g_bytes_unref(bytes) }
        var size: gsize = 0
        guard let start = g_bytes_get_data(bytes, &size), size > 0 else { return [:] }
        let text = String(decoding: UnsafeRawBufferPointer(start: start, count: Int(size)), as: UTF8.self)
        return parseTable(text)
    }

    /// The rows of a table's text: `<sf_name> <icon name>`; comment lines start with "#". Other
    /// lines are skipped (the generator writes none).
    static func parseTable(_ text: String) -> [String: String] {
        var names: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
            guard parts.count == 2 else { continue }
            names[String(parts[0])] = String(parts[1])
        }
        return names
    }
}
