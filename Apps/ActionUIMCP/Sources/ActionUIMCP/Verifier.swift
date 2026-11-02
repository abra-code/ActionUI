// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Verifier.swift - the ActionUIVerifier library, set up for agent documents: validated as
// deployed to this system, with the built-in schemas from the library's resource bundle and add-on
// schemas found the way the library's own tool finds them.
//
// The resource bundle (ActionUI_ActionUIVerifier, built next to the executable) is found by name in
// the executable's resolved folder, so a launch through a symlink on PATH still finds it.
// ACTIONUI_MCP_SCHEMA_DIR names another schemas directory instead.
// Without schemas the server still runs; only these checks are skipped.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUIVerifier

enum Verifier {
    /// Set up once, on first use. nil when no schemas were found or they failed to load.
    static let validator: DocumentValidator? = {
        guard let schemas = schemasDirectory() else {
            HostSupport.logLine("[actionui-mcp] verifier schemas not found; property checks are skipped")
            return nil
        }
        do {
            let extra = SchemaSet.discoverAddOnDirectories(schemasDirectory: schemas, includeCheckout: !isPackaged(schemas))
            let set = try SchemaSet(primary: schemas, extra: extra)
            return DocumentValidator(schemas: set, targetPlatform: HostPlatform.verifierPlatform)
        } catch {
            HostSupport.logLine("[actionui-mcp] could not load verifier schemas from \(schemas.path): \(error.displayText)")
            return nil
        }
    }()

    static let unavailableWarning = "schema checks (element types, property names and value types, enum values, required properties) were skipped: the ActionUIVerifier schemas were not found next to the server"

    /// Whether `schemas` are the ones a Linux package ships beside the server
    /// (Scripts/make-linux-mcp-package.sh): then they hold the add-ons this server has, and the
    /// ActionUI checkout the server was built from, which may still be on the machine, has others
    /// (QuickLook, Diff) that it cannot show. Elsewhere add-on schemas are found as before.
    private static func isPackaged(_ schemas: URL) -> Bool {
        #if os(Linux)
        guard let executable = HostSupport.executablePath else { return false }
        let shipped = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("share/actionui/schemas")
        return schemas.standardizedFileURL.path == shipped.standardizedFileURL.path
        #else
        return false
        #endif
    }

    private static func schemasDirectory() -> URL? {
        func hasSchemas(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.appendingPathComponent("View.json").path)
        }
        if let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_SCHEMA_DIR"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if hasSchemas(url) { return url }
            HostSupport.logLine("[actionui-mcp] ACTIONUI_MCP_SCHEMA_DIR=\(path) holds no View.json; looking elsewhere")
        }
        #if os(Linux)
        // The library has no resource bundle on Linux; it finds its schemas by path.
        return SchemaSet.bundledSchemasDirectory
        #else
        guard let resources = HostSupport.resourceFolder(ofBundle: "ActionUI_ActionUIVerifier") else { return nil }
        let schemas = resources.appendingPathComponent("Schemas")
        return hasSchemas(schemas) ? schemas : nil
        #endif
    }
}
