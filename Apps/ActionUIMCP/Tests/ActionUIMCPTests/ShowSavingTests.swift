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

/// The Save button of a `show` window: what each kind saves, and the CSV and unified diff writers.

private func save(_ arguments: [String: JSONValue]) throws -> ShowSave? {
    try ViewerSpec(arguments: arguments.merging(["title": "Q3: sales/costs"]) { given, _ in given }).save
}

@Test func eachKindSavesItsContent() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("show-save-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("plot.png")
    try Data([0]).write(to: file)
    let real = file.resolvingSymlinksInPath().path

    #expect(try save(["kind": "image", "path": .string(file.path)]) == ShowSave(content: .file(path: real), suggestedName: "plot.png"))
    #expect(try save(["kind": "markdown", "text": "# Hi"]) == ShowSave(content: .text("# Hi"), suggestedName: "Q3- sales-costs.md"))
    #expect(try save(["kind": "text", "text": "hi"])?.suggestedName == "Q3- sales-costs.txt")
    #expect(try save(["kind": "web", "text": "<p>hi</p>"]) == ShowSave(content: .text("<p>hi</p>"), suggestedName: "Q3- sales-costs.html"))
    #expect(try save(["kind": "table", "columns": ["A", "B"]]) == ShowSave(content: .table(columns: ["A", "B"]), suggestedName: "Q3- sales-costs.csv"))
    #expect(try save(["kind": "diff", "old_text": "a", "new_path": .string(file.path)])
            == ShowSave(content: .diff(old: DiffSideSource(text: "a", path: nil), new: DiffSideSource(text: nil, path: file.path)),
                        suggestedName: "Q3- sales-costs.diff"))
    // Content from the network has Copy URL instead.
    for kind in ["image", "video", "web"] {
        #expect(try save(["kind": .string(kind), "url": "https://example.com/x"]) == nil, "\(kind)")
    }
}

@Test func aTitleBecomesAFileName() {
    #expect(ShowSave.fileName(from: "a/b:c") == "a-b-c")
    #expect(ShowSave.fileName(from: "..hidden") == "hidden")
    #expect(ShowSave.fileName(from: " \n ") == "Untitled")
    #expect(ShowSave.fileName(from: "two\nlines") == "two lines")
}

@Test func csvQuotesWhatNeedsQuoting() {
    let csv = ShowSave.csv(columns: ["Name", "Note"], rows: [["a,b", "say \"hi\""], ["line\nbreak", "plain"]])
    #expect(csv == "Name,Note\r\n\"a,b\",\"say \"\"hi\"\"\"\r\n\"line\nbreak\",plain\r\n")
    // A comma or quote followed by a combining mark is still a comma or quote.
    #expect(ShowSave.csv(columns: ["a,\u{301}b", "x\"\u{301}y"], rows: []) == "\"a,\u{301}b\",\"x\"\"\u{301}y\"\r\n")
}

@Test func unifiedDiffMatchesDiffU() throws {
    #expect(try ShowSave.unifiedDiff(oldText: "a\nb\nc\n", newText: "a\nB\nc\n", oldName: "old", newName: "new")
            == "--- old\n+++ new\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n")
    // An empty side is named by the line before it.
    #expect(try ShowSave.unifiedDiff(oldText: "", newText: "x\n", oldName: "o", newName: "n") == "--- o\n+++ n\n@@ -0,0 +1 @@\n+x\n")
    #expect(try ShowSave.unifiedDiff(oldText: "x\n", newText: "", oldName: "o", newName: "n") == "--- o\n+++ n\n@@ -1 +0,0 @@\n-x\n")
    // Far apart changes make two hunks, each with three lines of context.
    let old = (1...20).map(String.init).joined(separator: "\n") + "\n"
    let new = old.replacingOccurrences(of: "\n2\n", with: "\ntwo\n").replacingOccurrences(of: "\n19\n", with: "\nnineteen\n")
    let diff = try ShowSave.unifiedDiff(oldText: old, newText: new, oldName: "o", newName: "n")
    #expect(diff.components(separatedBy: "\n").filter { $0.hasPrefix("@@") } == ["@@ -1,5 +1,5 @@", "@@ -16,5 +16,5 @@"])
    #expect(try ShowSave.unifiedDiff(oldText: "same\n", newText: "same\n", oldName: "o", newName: "n") == "")
}

@Test func unifiedDiffMarksALastLineWithNoLineBreak() throws {
    let note = "\\ No newline at end of file\n"
    // Only the final line break differs.
    #expect(try ShowSave.unifiedDiff(oldText: "a\nc", newText: "a\nc\n", oldName: "o", newName: "n")
            == "--- o\n+++ n\n@@ -1,2 +1,2 @@\n a\n-c\n" + note + "+c\n")
    #expect(try ShowSave.unifiedDiff(oldText: "a\nc\n", newText: "a\nc", oldName: "o", newName: "n")
            == "--- o\n+++ n\n@@ -1,2 +1,2 @@\n a\n-c\n+c\n" + note)
    // Neither side ends with one: a changed last line on both sides, an unchanged one once.
    #expect(try ShowSave.unifiedDiff(oldText: "a\nc", newText: "a\nC", oldName: "o", newName: "n")
            == "--- o\n+++ n\n@@ -1,2 +1,2 @@\n a\n-c\n" + note + "+C\n" + note)
    #expect(try ShowSave.unifiedDiff(oldText: "a\nc", newText: "A\nc", oldName: "o", newName: "n")
            == "--- o\n+++ n\n@@ -1,2 +1,2 @@\n-a\n+A\n c\n" + note)
    #expect(try ShowSave.unifiedDiff(oldText: "c", newText: "c", oldName: "o", newName: "n") == "")
}
