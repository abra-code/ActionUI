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
// The pages come from the documentation resource bundles that SwiftPM builds next to the
// executable (ActionUI_ActionUIDocumentation.bundle and one per add-on). They are found by name
// rather than through each package's Bundle.module accessor, which stops the process when its
// bundle is missing: a binary copied without its bundles then serves fewer pages, not a crash.

import Foundation
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
            FileHandle.standardError.write(Data("[actionui-mcp] documentation bundles not found; no docs resources\n".utf8))
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
        var result = text
        for (pattern, template) in [(#"\]\(Schemas/([A-Za-z0-9_]+)\.md\)"#, "](\(prefix)elements/$1)"),
                                    (#"\]\(Elements/([A-Za-z0-9_]+)\.json\)"#, "](\(prefix)templates/$1)"),
                                    (#"\]\(ActionUI-Elements\.md\)"#, "](\(prefix)elements)"),
                                    (#"\]\(ActionUI-JSON-Guide\.md\)"#, "](\(prefix)guide)")] {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result
    }

    /// The Resources folder of each documentation bundle found next to the executable or in the
    /// app bundle's Resources, in `bundleNames` order.
    private static func resourceFolders() -> [URL] {
        // Not CommandLine.arguments[0]: a client launching the bare name through PATH passes just
        // "actionui-mcp", which would resolve against the working directory.
        let executableFolder = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        let searchFolders = [executableFolder, Bundle.main.resourceURL].compactMap { $0 }
        return bundleNames.compactMap { name in
            for folder in searchFolders {
                if let bundle = Bundle(url: folder.appendingPathComponent(name + ".bundle")), let resources = bundle.resourceURL {
                    return resources
                }
            }
            return nil
        }
    }

    private static func contents(of folder: URL, extension fileExtension: String) -> [(name: String, url: URL)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == fileExtension && !$0.lastPathComponent.hasPrefix(".") }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
    }
}
