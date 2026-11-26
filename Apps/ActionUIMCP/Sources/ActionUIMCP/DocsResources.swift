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
// The actionui_docs tool (ToolsDocs.swift) serves the same pages from the same Index, for clients
// that show the model tools but not resources.
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

    /// One page of the reference: its file and MIME type.
    struct Page: Sendable {
        let url: URL
        let mimeType: String
    }

    /// The reference's URI -> file table, which both the resources and the actionui_docs tool read,
    /// so the two always serve the same text.
    struct Index: Sendable {
        /// Every page by URI.
        let pages: [String: Page]
        /// What resources/list returns: the guide, the index, then each element page by name.
        let listed: [MCPResource]

        /// Built from documentation folders (each holding Schemas/ and Elements/), core first: on a
        /// name clash the first folder's page wins. Element pages and templates come from every folder.
        init(folders: [URL]) {
            var pages: [String: Page] = [:]
            var listed: [MCPResource] = []
            if let core = folders.first {
                for (file, uri, title) in [("ActionUI-JSON-Guide.md", "guide", "ActionUI JSON guide"),
                                           ("ActionUI-Elements.md", "elements", "ActionUI element index")] {
                    let url = core.appendingPathComponent(file)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    pages[prefix + uri] = Page(url: url, mimeType: "text/markdown")
                    listed.append(MCPResource(uri: prefix + uri, name: uri, title: title, mimeType: "text/markdown"))
                }
            }
            var elementPages: [String: URL] = [:]
            for folder in folders {
                for page in contents(of: folder.appendingPathComponent("Schemas"), extension: "md") where elementPages[page.name] == nil {
                    elementPages[page.name] = page.url
                }
                for template in contents(of: folder.appendingPathComponent("Elements"), extension: "json") {
                    let uri = prefix + "templates/" + template.name
                    if pages[uri] == nil { pages[uri] = Page(url: template.url, mimeType: "application/json") }
                }
            }
            for (name, url) in elementPages.sorted(by: { $0.key < $1.key }) {
                let uri = prefix + "elements/" + name
                pages[uri] = Page(url: url, mimeType: "text/markdown")
                listed.append(MCPResource(uri: uri, name: name, title: "\(name) element", mimeType: "text/markdown"))
            }
            self.pages = pages
            self.listed = listed
        }

        /// The page at `uri` as resources/read returns it, links pointed at actionui:// URIs; nil for
        /// an unknown URI or a file that cannot be read.
        func read(_ uri: String) -> (mimeType: String, text: String)? {
            guard let page = pages[uri], let text = try? String(contentsOf: page.url, encoding: .utf8) else { return nil }
            return (page.mimeType, page.mimeType == "text/markdown" ? rewriteLinks(text) : text)
        }

        /// The element types with a page, sorted.
        var elementNames: [String] {
            pages.keys.filter { $0.hasPrefix(prefix + "elements/") }.map { String($0.dropFirst(prefix.count + "elements/".count)) }.sorted()
        }
    }

    /// The URI of a page: "guide", "elements", "elements/<Type>" or "templates/<Type>".
    static func uri(_ path: String) -> String { prefix + path }

    /// The reference found next to the server, built once; nil when no documentation was found.
    static let index: Index? = {
        let folders = resourceFolders()
        guard !folders.isEmpty else {
            HostSupport.logLine("[actionui-mcp] documentation bundles not found; no docs resources")
            return nil
        }
        return Index(folders: folders)
    }()

    /// nil when no documentation was found; the server then offers no resources (actionui_docs then
    /// says the reference is not installed).
    static func make(index: Index? = DocsResources.index) -> MCPResources? {
        guard let index else { return nil }
        let templates = [
            MCPResourceTemplate(uriTemplate: prefix + "elements/{type}", name: "element",
                                description: "Properties, value and behavior of one ActionUI element type, such as Button or TextField.",
                                mimeType: "text/markdown"),
            MCPResourceTemplate(uriTemplate: prefix + "templates/{type}", name: "template",
                                description: "A JSON template of one ActionUI element type with its common properties, to copy into ActionUI JSON.",
                                mimeType: "application/json"),
        ]
        return MCPResources(resources: index.listed, templates: templates) { index.read($0) }
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

    #if os(Linux) || os(Windows)
    /// The documentation folders on Linux, core first: the name in an installed package, and the
    /// folder in the checkout.
    private static let linuxFolders = [
        ("ActionUI", "Documentation"),
        ("ActionUICachedImage", "Add-ons/ActionUICachedImage/Documentation"),
        ("ActionUIDiff", "Add-ons/ActionUIDiff/Documentation"),
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
