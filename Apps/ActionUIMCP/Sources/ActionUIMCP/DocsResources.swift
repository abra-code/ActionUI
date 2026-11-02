// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// DocsResources.swift - ActionUI's element reference as MCP resources, so a client without the
// actionui skill can still look up elements and properties:
//   actionui://docs/guide              the JSON guide
//   actionui://docs/elements           the element index
//   actionui://docs/elements/<Type>    one element's properties (core and add-ons)
//   actionui://docs/templates/<Type>   a ready-to-edit JSON template for one element
//
// On macOS the pages come from the documentation resource bundles that SwiftPM builds next to the
// executable (ActionUI_ActionUIDocumentation.bundle and one per add-on). They are found by name
// rather than through each package's Bundle.module accessor, which stops the process when its
// bundle is missing: a binary copied without its bundles then serves fewer pages, not a crash.
//
// Linux builds no resource bundles (Bundle.module needs full Foundation), so the pages are plain
// folders: <prefix>/share/actionui/docs/<name> for a server in <prefix>/bin, as the Linux package
// lays them out (Scripts/make-linux-mcp-package.sh), else the Documentation folders of the ActionUI
// checkout the server was built from. Only the add-ons Linux has are served.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import MCPStdio

enum DocsResources {
    /// Documentation bundles, core first: on a name clash the core page wins.
    private static let bundleNames = [
        "ActionUI_ActionUIDocumentation",
        "ActionUIQuickLook_ActionUIQuickLookDocumentation",
        "ActionUIDiff_ActionUIDiffDocumentation",
        "ActionUICachedImage_ActionUICachedImageDocumentation",
        "ActionUIRichText_ActionUIRichTextDocumentation",
    ]
    private static let prefix = "actionui://docs/"

    /// nil when no documentation bundle was found; the server then offers no resources.
    static func make() -> MCPResources? {
        let folders = resourceFolders()
        guard !folders.isEmpty else {
            HostSupport.logLine("[actionui-mcp] documentation bundles not found; no docs resources")
            return nil
        }
        // URI -> file, built once. Element pages and templates come from every bundle.
        var files: [String: (url: URL, mimeType: String)] = [:]
        var listed: [MCPResource] = []
        let core = folders[0]
        for (file, uri, title) in [("ActionUI-JSON-Guide.md", "guide", "ActionUI JSON guide"),
                                   ("ActionUI-Elements.md", "elements", "ActionUI element index")] {
            let url = core.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            files[prefix + uri] = (url, "text/markdown")
            listed.append(MCPResource(uri: prefix + uri, name: uri, title: title, mimeType: "text/markdown"))
        }
        var elementPages: [String: URL] = [:]
        for folder in folders {
            for page in contents(of: folder.appendingPathComponent("Schemas"), extension: "md") where elementPages[page.name] == nil {
                elementPages[page.name] = page.url
            }
            for template in contents(of: folder.appendingPathComponent("Elements"), extension: "json") {
                let uri = prefix + "templates/" + template.name
                if files[uri] == nil { files[uri] = (template.url, "application/json") }
            }
        }
        for (name, url) in elementPages.sorted(by: { $0.key < $1.key }) {
            let uri = prefix + "elements/" + name
            files[uri] = (url, "text/markdown")
            listed.append(MCPResource(uri: uri, name: name, title: "\(name) element", mimeType: "text/markdown"))
        }
        let templates = [
            MCPResourceTemplate(uriTemplate: prefix + "elements/{type}", name: "element",
                                description: "Properties, value and behavior of one ActionUI element type, such as Button or TextField.",
                                mimeType: "text/markdown"),
            MCPResourceTemplate(uriTemplate: prefix + "templates/{type}", name: "template",
                                description: "A JSON template of one ActionUI element type with its common properties, to copy into a document.",
                                mimeType: "application/json"),
        ]
        let table = files
        return MCPResources(resources: listed, templates: templates) { uri in
            guard let entry = table[uri], let text = try? String(contentsOf: entry.url, encoding: .utf8) else { return nil }
            return (entry.mimeType, entry.mimeType == "text/markdown" ? rewriteLinks(text) : text)
        }
    }

    /// The pages link to each other by bundle-relative file paths ("Schemas/Button.md"), which mean
    /// nothing under actionui://. Point them at the resources instead, so a client that follows a
    /// link reaches a page this server serves.
    private static func rewriteLinks(_ text: String) -> String {
        text.replacing(#/\]\(Schemas\/([A-Za-z0-9_]+)\.md\)/#) { "](\(prefix)elements/\($0.1))" }
            .replacing(#/\]\(Elements\/([A-Za-z0-9_]+)\.json\)/#) { "](\(prefix)templates/\($0.1))" }
            .replacing("](ActionUI-Elements.md)", with: "](\(prefix)elements)")
            .replacing("](ActionUI-JSON-Guide.md)", with: "](\(prefix)guide)")
    }

    #if os(Linux)
    /// The documentation folders on Linux, core first: the name in an installed package, and the
    /// folder in the checkout.
    private static let linuxFolders = [
        ("ActionUI", "Documentation"),
        ("ActionUICachedImage", "Add-ons/ActionUICachedImage/Documentation"),
        ("ActionUIRichText", "Add-ons/ActionUIRichText/Documentation"),
    ]

    /// Each documentation folder found, in `linuxFolders` order: the installed package's, else the
    /// checkout's.
    private static func resourceFolders() -> [URL] {
        let installed = HostSupport.executablePath.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("share/actionui/docs")
        }
        // This file is <repo>/Apps/ActionUIMCP/Sources/ActionUIMCP/DocsResources.swift.
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo = repo.deletingLastPathComponent() }
        return linuxFolders.compactMap { name, checkoutPath in
            [installed?.appendingPathComponent(name), repo.appendingPathComponent(checkoutPath)]
                .compactMap { $0 }
                .first { HostSupport.isFolder(atPath: $0.appendingPathComponent("Schemas").path) == true }
        }
    }
    #else
    /// The Resources folder of each documentation bundle found, in `bundleNames` order.
    private static func resourceFolders() -> [URL] {
        bundleNames.compactMap(HostSupport.resourceFolder(ofBundle:))
    }
    #endif

    private static func contents(of folder: URL, extension fileExtension: String) -> [(name: String, url: URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
            .map { folder.appendingPathComponent($0) }
            .filter { $0.pathExtension == fileExtension }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
    }
}
