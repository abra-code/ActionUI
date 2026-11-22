// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// MCPTrustPolicy.swift - how far the server trusts the windows it shows: as ActionUIViewer trusts
// the file its user names.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI

/// The server's trust policy. Every window it shows is ActionUI JSON it wrote itself, for its client,
/// into its own folder (the session folder; a kept window's spool folder in the keeper process): a
/// file there loaded as a window's root is trusted, as the Viewer trusts the file its user names,
/// so the window may show the image, video or file it was asked to show. A local file that content
/// loads in turn takes that content's trust, as in the Viewer. Anything else keeps ActionUI's own
/// rules: ActionUI JSON from a server is less trusted, and so is all it loads.
struct MCPTrustPolicy: ActionUITrustPolicy {
    /// The folder whose ActionUI JSON files are the server's own windows.
    let windowFolder: String

    func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?,
               byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust {
        guard case .file(let path) = source else { return byDefault }
        if let parent { return parent.trust }
        return ActionUIResourceFolder.isFile(URL(fileURLWithPath: path), inside: windowFolder) ? .trusted : byDefault
    }

    /// Installs the policy for windows staged in `folder`. Before the first window loads.
    @MainActor
    static func install(windowFolder folder: URL) {
        ActionUIModel.shared.trustPolicy = MCPTrustPolicy(windowFolder: folder.path)
    }
}
