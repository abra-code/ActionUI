// Sources/Styling/SymbolNames.swift
/*
 SF Symbol names, as ActionUI JSON gives them (systemName, systemImage), mapped to icon theme names.
 SF Symbols may not be shipped off Apple platforms, so a name shows the Material Symbols Rounded icon
 that sf_to_material.map gives it, as on Android and Web, at the row's fill and weight, or, for a
 name that map lacks, the Fluent System Icons glyph of sf_to_fluent.map, as on Windows (SymbolIcons);
 GTK recolors it with the text color as SF Symbols are.

 The lookup is the exact name, as on Android and Web: a name the maps lack is not tried again
 without a ".fill" or ".circle" suffix. A name with a "-" is taken as an icon theme name already
 ("document-save-symbolic"), so ActionUI JSON can name a Linux icon with a ":linux" suffixed key.
 Anything else shows image-missing, logged once per name.
*/

@MainActor
enum SymbolNames {
    /// What an unknown symbol shows.
    static let missing = "image-missing-symbolic"

    private static var reportedMissing: Set<String> = []

    /// The icon theme name for `symbol`.
    static func iconName(_ symbol: String) -> String {
        if let name = lookup(symbol) {
            return name
        }
        if reportedMissing.insert(symbol).inserted {
            ActionUIModel.shared.logger.log("No Linux icon for the symbol \"\(symbol)\"; showing \(missing)", .warning)
        }
        return missing
    }

    /// The icon for `symbol`, nil when there is none.
    static func lookup(_ symbol: String) -> String? {
        if symbol.contains("-") {
            return symbol
        }
        return SymbolIcons.iconName(symbol)
    }
}
