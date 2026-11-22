// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
import ActionUI
@testable import ActionUIMCP

/// A window file the server staged in its folder is trusted, as the Viewer trusts the file its
/// user names, so its Image, VideoPlayer or QuickLook may read the user's file; what trusted
/// content loads in turn keeps that trust; a file elsewhere and remote ActionUI JSON keep
/// ActionUI's own rules.
@MainActor
@Test func theServersOwnWindowFilesAreTrusted() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-trust-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let window = folder.appendingPathComponent("w1.json")
    try Data("{}".utf8).write(to: window)
    // As the loader gives it: symbolic links resolved (the temporary folder is behind one on macOS).
    let windowPath = window.resolvingSymlinksInPath().standardizedFileURL.path
    let policy = MCPTrustPolicy(windowFolder: folder.path)

    #expect(policy.trust(for: .file(windowPath), inside: nil, byDefault: .lessTrusted) == .trusted,
            "a window file the server staged")
    #expect(policy.trust(for: .file("/etc/hosts"), inside: nil, byDefault: .lessTrusted) == .lessTrusted,
            "a window file elsewhere keeps ActionUI's rule")
    let trusted = JSONContentOrigin(source: .file(windowPath), trust: .trusted, parentID: nil)
    let remote = JSONContentOrigin(source: .remote(URL(string: "https://example.com/a.json")!), trust: .lessTrusted, parentID: nil)
    #expect(policy.trust(for: .file("/Users/me/panel.json"), inside: trusted, byDefault: .lessTrusted) == .trusted,
            "a local file the server's own window loads takes its trust")
    #expect(policy.trust(for: .file(windowPath), inside: remote, byDefault: .lessTrusted) == .lessTrusted,
            "remote content cannot name a window file and get trusted content")
    #expect(policy.trust(for: .remote(URL(string: "https://example.com/b.json")!), inside: trusted, byDefault: .lessTrusted) == .lessTrusted,
            "remote ActionUI JSON keeps ActionUI's rule")
    // With trusted content, a local image outside the app's resources may be read.
    #expect(policy.allows(.readLocalFile("/Users/me/photo.png"), for: trusted))
    #expect(!policy.allows(.readLocalFile("/Users/me/photo.png"), for: remote))
}
