// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// ToolsDocs.swift - actionui_docs: the ActionUI JSON reference bundled with the server, as a tool.
// Every client shows the model its tools, while some never pass the server's instructions on and
// many offer resources to the user only: this is the route to the reference that always works. It
// reads DocsResources.index, as the resources do, so a page reads the same either way. It opens no
// window and works with no graphical session.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import MCPStdio

/// The sentence that show_ui's and validate_ui's descriptions start with. The server's
/// instructions (main.swift) say the same in their own words.
let readTheReferenceFirst = "Before writing ActionUI JSON, read the actionui skill if you have it, else call actionui_docs: the guide first (start from its Window Content example), then each element's page."

func docsTool() -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "topic": ["type": "string", "enum": ["guide", "elements", "element", "template"],
                      "description": "guide: how ActionUI JSON is written (read it first). elements: the index of element types. element: one element's page (needs type). template: a JSON template of one element (needs type)."],
            "type": ["type": "string",
                     "description": "For topic element or template: the element type, in the exact case of the element index, such as \"Form\" or \"TextField\"."],
        ],
        "required": ["topic"],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "actionui_docs",
        title: "ActionUI JSON reference",
        description: """
            The ActionUI JSON reference bundled with this server, for writing the `ui` that show_ui \
            and validate_ui take, and nothing else. topic guide: how ActionUI JSON is written, with a \
            Window Content example to start from (read it first); elements: the index of element \
            types; element (with type): one element's properties, value and behavior; template (with \
            type): a JSON template of that element to copy.
            """,
        inputSchema: input,
        annotations: ["readOnlyHint": true, "openWorldHint": false]
    ) { arguments, _ in
        let text = try DocsTool.text(topic: arguments["topic"]?.string, type: arguments["type"]?.string,
                                     index: DocsResources.index)
        return MCPToolResult(content: [["type": "text", "text": .string(text)]])
    }
}

enum DocsTool {
    /// The page for `topic` (and `type`), exactly as resources/read returns it for the same URI.
    static func text(topic: String?, type: String?, index: DocsResources.Index?) throws -> String {
        guard let topic else { throw MCPToolError("'topic' is required: guide, elements, element or template") }
        let path: String
        switch topic {
        case "guide", "elements":
            path = topic
        case "element", "template":
            guard let type, !type.isEmpty else {
                throw MCPToolError("'type' is required for topic \(topic): an element type such as Form or TextField (see topic elements)")
            }
            path = (topic == "element" ? "elements/" : "templates/") + type
        default:
            throw MCPToolError("'topic' must be guide, elements, element or template")
        }
        guard let index else { throw MCPToolError("the ActionUI reference is not installed with this server") }
        if let page = index.read(DocsResources.uri(path)) { return page.text }
        // guide and elements ignore `type`, so a missing page there is never "no element named <type>".
        guard topic == "element" || topic == "template", let type else {
            throw MCPToolError("the \(topic) page is not installed with this server")
        }
        let names = index.elementNames
        if topic == "template", names.contains(type) {
            throw MCPToolError("no template for \(type); its page is actionui_docs topic element, type \(type)")
        }
        let shown = oneLine(type, limit: 60)
        var message = "no element named \(shown); see actionui_docs topic elements"
        let close = closestNames(to: type, in: names)
        if !close.isEmpty { message += " (closest: " + close.joined(separator: ", ") + ")" }
        throw MCPToolError(message)
    }

    /// Up to 5 element names that `name` may have meant: the same name in another case, then names
    /// that contain it or that it contains.
    static func closestNames(to name: String, in names: [String]) -> [String] {
        let wanted = name.lowercased()
        guard wanted.count >= 2 else { return [] }
        let sameCase = names.filter { $0.lowercased() == wanted }
        let containing = names.filter {
            let candidate = $0.lowercased()
            return candidate != wanted && (candidate.contains(wanted) || (candidate.count >= 3 && wanted.contains(candidate)))
        }
        return Array((sameCase + containing).prefix(5))
    }
}
