// Plugins/SymbolIcons/plugin.swift
/*
 The build step that gives the Linux library its symbol icons. SF Symbols may not be shipped off
 Apple platforms, so each SF Symbol name maps to a Material Symbols Rounded glyph
 (ActionUIAndroid's sf_to_material.map, shared with Android and Web), drawn as a symbolic SVG icon.

 One command, run again when the map, the font or the tool changes: ActionUISymbolIcons --swift
 draws the icons into a folder (kept for inspection, under .build/plugins/outputs/), packs them and
 the map with glib-compile-resources into one GResource file, and writes that file into a Swift
 source the ActionUI target compiles in, so the library carries its icons wherever it is copied.
 The Swift file is the command's only declared output: SwiftPM takes any other output as a resource
 of the target, with a resource bundle and a Foundation-based Bundle.module the library must not
 have.

 The font is not in the repository: Tools/material_symbols/fetch-material-symbols-font.sh downloads
 the pinned release, and the build stops with that advice when it is missing.
*/

import Foundation
import PackagePlugin

@main
struct SymbolIconsPlugin: BuildToolPlugin {
    struct FontMissing: Error, CustomStringConvertible {
        let path: String
        var description: String {
            "The Material Symbols font is missing (\(path)). Download it with: "
                + "bash Tools/material_symbols/fetch-material-symbols-font.sh"
        }
    }

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let package = context.package.directoryURL
        let map = package.appending(path: "ActionUIAndroid/library/src/main/assets/symbols/sf_to_material.map")
        let font = package.appending(path: "Tools/material_symbols/font/MaterialSymbolsRounded.ttf")
        guard FileManager.default.fileExists(atPath: font.path) else {
            throw FontMissing(path: font.path)
        }
        let work = context.pluginWorkDirectoryURL
        let icons = work.appending(path: "icons")
        let source = work.appending(path: "MaterialSymbolsResource.swift")
        return [
            .buildCommand(
                displayName: "Building the symbol icons",
                executable: try context.tool(named: "ActionUISymbolIcons").url,
                arguments: ["--swift", map.path, font.path, icons.path, source.path],
                inputFiles: [map, font],
                outputFiles: [source]
            ),
        ]
    }
}
