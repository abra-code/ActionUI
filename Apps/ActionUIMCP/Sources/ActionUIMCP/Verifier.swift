// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Verifier.swift - the ActionUIVerifier library, set up for agent documents: validated as
// deployed to macOS, with the built-in schemas from the library's resource bundle and add-on
// schemas found the way the library's own tool finds them.
//
// The bundle (ActionUI_ActionUIVerifier.bundle, built next to the executable) is found by name in
// the executable's resolved folder, so a launch through a symlink on PATH still finds it.
// ACTIONUI_MCP_SCHEMA_DIR names another schemas directory instead.
// Without schemas the server still runs; only these checks are skipped.

import Foundation
import ActionUIVerifier

enum Verifier {
    /// Set up once, on first use. nil when no schemas were found or they failed to load.
    static let validator: DocumentValidator? = {
        guard let schemas = schemasDirectory() else {
            FileHandle.standardError.write(Data("[actionui-mcp] verifier schemas not found; property checks are skipped\n".utf8))
            return nil
        }
        do {
            let set = try SchemaSet(primary: schemas, extra: SchemaSet.discoverAddOnDirectories(schemasDirectory: schemas))
            return DocumentValidator(schemas: set, targetPlatform: "macos")
        } catch {
            FileHandle.standardError.write(Data("[actionui-mcp] could not load verifier schemas from \(schemas.path): \(error.localizedDescription)\n".utf8))
            return nil
        }
    }()

    static let unavailableWarning = "schema checks (element types, property names and value types, enum values, required properties) were skipped: the ActionUIVerifier schemas were not found next to the server"

    private static func schemasDirectory() -> URL? {
        func hasSchemas(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.appendingPathComponent("View.json").path)
        }
        if let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_SCHEMA_DIR"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if hasSchemas(url) { return url }
            FileHandle.standardError.write(Data("[actionui-mcp] ACTIONUI_MCP_SCHEMA_DIR=\(path) holds no View.json; looking elsewhere\n".utf8))
        }
        // Not CommandLine.arguments[0], which is only the bare name when launched through PATH.
        let folders = [Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
                       Bundle.main.resourceURL].compactMap { $0 }
        for folder in folders {
            if let resources = Bundle(url: folder.appendingPathComponent("ActionUI_ActionUIVerifier.bundle"))?.resourceURL {
                let schemas = resources.appendingPathComponent("Schemas")
                if hasSchemas(schemas) { return schemas }
            }
        }
        return nil
    }
}
