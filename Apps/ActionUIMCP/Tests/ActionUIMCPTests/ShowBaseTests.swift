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

/// `show`'s "base": the folder that relative image paths in markdown text resolve against.

private func show(_ arguments: [String: JSONValue]) throws -> ViewerSpec {
    try ViewerSpec(arguments: arguments.merging(["title": "Report"]) { given, _ in given })
}

private func content(_ spec: ViewerSpec) -> [String: Any]? {
    (spec.root["content"] as? [String: Any])?["properties"] as? [String: Any]
}

@Test func markdownTextResolvesAgainstTheBaseFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("show-base-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("plot.png")
    try Data([0]).write(to: file)

    let byFolder = try show(["kind": "markdown", "text": "![plot](plot.png)", "base": .string(dir.path)])
    #expect((content(byFolder)?["baseURL"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            == dir.standardizedFileURL.path)
    // A file names its folder.
    let byFile = try show(["kind": "markdown", "text": "![plot](plot.png)", "base": .string(file.path)])
    #expect((content(byFile)?["baseURL"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            == dir.standardizedFileURL.path)
    // Without one, nothing changes.
    #expect(content(try show(["kind": "markdown", "text": "x"]))?["baseURL"] == nil)
}

@Test func aBaseMustBeAnExistingAbsolutePathForMarkdown() throws {
    #expect(throws: MCPToolError.self) { try show(["kind": "markdown", "text": "x", "base": "relative/dir"]) }
    #expect(throws: MCPToolError.self) { try show(["kind": "markdown", "text": "x", "base": .string("/no/such/folder-\(UUID().uuidString)")]) }
    let dir = FileManager.default.temporaryDirectory.path
    #expect(throws: MCPToolError.self) { try show(["kind": "text", "text": "x", "base": .string(dir)]) }
    #expect(throws: MCPToolError.self) { try show(["kind": "web", "text": "<p>x</p>", "base": .string(dir)]) }
    // The wrong kind is named before the path is looked at.
    let wrongKind = #expect(throws: MCPToolError.self) { try show(["kind": "text", "text": "x", "base": "relative/dir"]) }
    #expect(wrongKind?.message.contains("'markdown' only") == true)
}
