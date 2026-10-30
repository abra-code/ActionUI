// Plugins/SymbolResourceCheck/plugin.swift
/*
 Warns, on every Linux build of the ActionUI target, when the Material Symbols icon resource is
 missing or older than the map or the font it is made from. The icons are generated before the
 build by Scripts/prepare-linux-symbols.sh (a build plugin cannot add C code to a target, and the
 icons go into the library as a C section, see CSymbolResource). Without them the build still
 succeeds and SF Symbols show the missing-icon picture, so the warning names the script. It runs
 no command: SwiftPM shows its warning near the top of every build's output, also when nothing is
 compiled again.
*/

import Foundation
import PackagePlugin

@main
struct SymbolResourceCheckPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let package = context.package.directoryURL
        let folder = package.appending(path: "ActionUIAdwaita/CSymbolResource/generated")
        let generated = folder.appending(path: "symbols-resource.inc")
        // The script rewrites the resource only when it changed, and stamps every run.
        let stamp = folder.appending(path: "stamp")
        let inputs = [
            package.appending(path: "ActionUIAndroid/library/src/main/assets/symbols/sf_to_material.map"),
            package.appending(path: "Tools/material_symbols/font/MaterialSymbolsRounded.ttf"),
            package.appending(path: "Tools/material_symbols/generate-symbol-icons.c"),
        ]
        let script = package.appending(path: "Scripts/prepare-linux-symbols.sh").path
        guard let resourceDate = modificationDate(generated) else {
            Diagnostics.warning("""
                ActionUI: NO SYMBOL ICONS. This build of ActionUI has no Material Symbols icons, so every SF Symbol \
                shows the missing-icon picture. Run first: bash \(script)
                """)
            return []
        }
        let built = modificationDate(stamp) ?? resourceDate
        if let newer = inputs.first(where: { (modificationDate($0) ?? .distantPast) > built }) {
            Diagnostics.warning("""
                ActionUI: SYMBOL ICONS OUT OF DATE. \(newer.lastPathComponent) changed after the icons were generated. \
                Run: bash \(script)
                """)
        }
        return []
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
