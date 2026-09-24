// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// SchemaSet.swift - the element schemas the validator checks against. The built-in schemas are
// ActionUIVerifier/Schemas, bundled into this library as a resource (the Python verifier in
// Tools/verifier reads the same files). Add-on schemas come from extra directories: this
// library cannot depend on the add-on packages, which depend on ActionUI core.

import Foundation

/// Element schemas loaded from a primary directory (the built-in elements) and extra directories
/// (add-ons). On a name collision the primary directory wins, so an add-on cannot shadow a
/// built-in element; among the extra directories, the first one listed wins.
public struct SchemaSet: Sendable {
    private let schemas: [String: JSONValue]
    public let knownTypes: Set<String>

    /// Loads every `*.json` schema in `primary`, then in each of `extra`. Throws when a schema is
    /// not valid JSON or `primary` holds no View.json.
    public init(primary: URL, extra: [URL] = []) throws {
        var loaded: [String: JSONValue] = [:]
        for directory in [primary] + extra {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            // Hidden files are skipped (the Python verifier's glob lists them, but it only opens a
            // schema when an element names its type; this loader parses every file, and an
            // AppleDouble "._Text.json" would fail the whole set).
            for file in files.sorted(by: { $0.path < $1.path })
            where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
                let name = file.deletingPathExtension().lastPathComponent
                guard loaded[name] == nil else {
                    continue
                }
                let data = try Data(contentsOf: file)
                loaded[name] = JSONValue(any: try JSONSerialization.jsonObject(with: data))
            }
        }
        guard loaded["View"] != nil else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: primary.appendingPathComponent("View.json").path])
        }
        schemas = loaded
        knownTypes = Set(loaded.keys).subtracting(["View"])
    }

    /// The built-in schemas bundled with this library, plus `extra` add-on directories.
    public static func bundled(extra: [URL] = []) throws -> SchemaSet {
        guard let directory = bundledSchemasDirectory else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Schemas"])
        }
        return try SchemaSet(primary: directory, extra: extra)
    }

    /// The `Schemas` directory in this library's resource bundle.
    public static var bundledSchemasDirectory: URL? {
        Bundle.module.url(forResource: "Schemas", withExtension: nil)
    }

    /// Add-on schema directories found without being named, as the Python verifier's
    /// discover_addon_schema_dirs finds them:
    ///   1. `<schemasDirectory>/add-ons/<AddOn>/`, then `add-ons/` itself - where a packaging step
    ///      copies each add-on's schemas (the Skill build and OMC's AppletBuilder do);
    ///   2. `<repo>/Add-ons/<AddOn>/Schemas/` in the ActionUI checkout this library was built
    ///      from, when that checkout still exists.
    public static func discoverAddOnDirectories(schemasDirectory: URL) -> [URL] {
        var directories: [URL] = []
        let reserved = schemasDirectory.appendingPathComponent("add-ons")
        if isDirectory(reserved) {
            directories += subdirectories(reserved)
            directories.append(reserved)
        }
        // This file is <repo>/ActionUIVerifier/SchemaSet.swift.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        directories += subdirectories(repo.appendingPathComponent("Add-ons"))
            .map { $0.appendingPathComponent("Schemas") }
            .filter(isDirectory)
        return directories
    }

    func schema(_ name: String) -> [String: JSONValue]? { schemas[name]?.object }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static func subdirectories(_ url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter(isDirectory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
