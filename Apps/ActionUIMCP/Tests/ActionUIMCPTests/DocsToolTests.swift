// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif
import Foundation
import MCPStdio
import Testing
@testable import ActionUIMCP

/// actionui_docs serves what resources/read serves, here from the checkout's pages: a test process
/// has no documentation bundles beside it.

private let checkoutIndex: DocsResources.Index = {
    // This file is <repo>/Apps/ActionUIMCP/Tests/ActionUIMCPTests/DocsToolTests.swift.
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repo = repo.deletingLastPathComponent() }
    let folders = ["Documentation", "Add-ons/ActionUIDiff/Documentation", "Add-ons/ActionUIRichText/Documentation"]
    return DocsResources.Index(folders: folders.map { repo.appendingPathComponent($0) })
}()

private func docsError(topic: String?, type: String?, index: DocsResources.Index? = checkoutIndex) -> String? {
    do {
        _ = try DocsTool.text(topic: topic, type: type, index: index)
        return nil
    } catch let error as MCPToolError {
        return error.message
    } catch {
        return "\(error)"
    }
}

@Test func eachDocsTopicReadsAsTheResource() throws {
    let resources = try #require(DocsResources.make(index: checkoutIndex))
    for (topic, type, path) in [("guide", nil, "guide"), ("elements", nil, "elements"),
                                ("element", "Form", "elements/Form"), ("element", "RichText", "elements/RichText"),
                                ("template", "TextField", "templates/TextField")] as [(String, String?, String)] {
        let text = try DocsTool.text(topic: topic, type: type, index: checkoutIndex)
        #expect(text == resources.read(DocsResources.uri(path))?.text, "\(path)")
    }
    #expect(try DocsTool.text(topic: "guide", type: nil, index: checkoutIndex).contains("Window Content"))
    // Links point at the server's URIs, not at files.
    let elements = try DocsTool.text(topic: "elements", type: nil, index: checkoutIndex)
    #expect(elements.contains("](actionui://docs/elements/Form)"))
    #expect(!elements.contains("](Schemas/"))
    let template = try DocsTool.text(topic: "template", type: "TextField", index: checkoutIndex)
    let object = try JSONSerialization.jsonObject(with: Data(template.utf8)) as? [String: Any]
    #expect(object?["type"] as? String == "TextField")
}

@Test func badDocsArgumentsSayWhatToDo() {
    #expect(docsError(topic: nil, type: nil) == "'topic' is required: guide, elements, element or template")
    #expect(docsError(topic: "manual", type: nil) == "'topic' must be guide, elements, element or template")
    #expect(docsError(topic: "element", type: nil)?.hasPrefix("'type' is required for topic element") == true)
    #expect(docsError(topic: "template", type: "")?.hasPrefix("'type' is required for topic template") == true)
    #expect(docsError(topic: "element", type: "Nope") == "no element named Nope; see actionui_docs topic elements")
    #expect(docsError(topic: "element", type: "textfield")
            == "no element named textfield; see actionui_docs topic elements (closest: TextField, Text)")
    #expect(docsError(topic: "element", type: "Field")?.contains("SecureField") == true)
    // A type cannot reach the URI's other parts.
    #expect(docsError(topic: "element", type: "../guide") != nil)
    #expect(docsError(topic: "guide", type: nil, index: nil) == "the ActionUI reference is not installed with this server")
    // An index without the core folder has no guide; the ignored type does not change the message.
    let noGuide = DocsResources.Index(folders: [])
    #expect(docsError(topic: "guide", type: "Form", index: noGuide) == "the guide page is not installed with this server")
}

@Test func theDocsToolIsReadOnly() {
    let tool = docsTool()
    #expect(tool.name == "actionui_docs")
    #expect(tool.annotations?["readOnlyHint"] == true)
    #expect(tool.annotations?["openWorldHint"] == false)
}
