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

/// The bottom bar of a `show` window: the file or web address the content came from.

private func footer(_ arguments: [String: JSONValue]) throws -> ShowFooter {
    try ViewerSpec(arguments: arguments.merging(["title": "Shown"]) { given, _ in given }).footer()
}

@Test func theBarNamesTheFileBehindFileBackedKinds() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("show-footer-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("notes.txt")
    try Data("notes".utf8).write(to: file)
    // A link is shown as the file it leads to.
    let link = dir.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    let real = file.resolvingSymlinksInPath().path

    for kind in ["file", "image", "video"] {
        let shown = try footer(["kind": .string(kind), "path": .string(link.path)])
        #expect(shown.path == real, "\(kind)")
        #expect(shown.url == nil, "\(kind)")
    }
}

@Test func theBarNamesTheAddressBehindNetworkKinds() throws {
    for kind in ["image", "video", "web"] {
        let shown = try footer(["kind": .string(kind), "url": "https://example.com/a/b"])
        #expect(shown.url == "https://example.com/a/b", "\(kind)")
        #expect(shown.path == nil, "\(kind)")
    }
}

@Test func inlineContentHasNoSourceInTheBar() throws {
    let before = Date()
    for arguments: [String: JSONValue] in [["kind": "markdown", "text": "x"], ["kind": "text", "text": "x"],
                                           ["kind": "web", "text": "<p>x</p>"],
                                           ["kind": "diff", "old_text": "a", "new_text": "b"],
                                           ["kind": "table", "columns": ["A"], "rows": [["1"]]]] {
        let shown = try footer(arguments)
        #expect(shown.path == nil && shown.url == nil, "\(arguments)")
        #expect(shown.shownAt >= before)
    }
}
