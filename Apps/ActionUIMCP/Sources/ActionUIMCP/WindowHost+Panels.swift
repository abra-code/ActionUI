// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost+Panels.swift - pick_path: the system open and save panels. A panel runs free-standing,
// so the main loop keeps serving other tool calls while the user browses.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import MCPStdio

struct PanelSpec {
    enum Kind: String, CaseIterable { case file, folder, save }

    let kind: Kind
    let title: String?
    let message: String?
    let allowedTypes: [HostPlatform.FileType]
    let multiple: Bool
    let directory: URL?
    let defaultName: String?

    init(arguments: [String: JSONValue]) throws {
        let kindName = arguments["kind"]?.string ?? "file"
        guard let kind = Kind(rawValue: kindName) else {
            throw MCPToolError("'kind' must be one of: file, folder, save")
        }
        self.kind = kind
        title = arguments["title"]?.string
        message = arguments["message"]?.string
        multiple = arguments["multiple"]?.bool ?? false
        defaultName = arguments["default_name"]?.string
        var types: [HostPlatform.FileType] = []
        for name in (arguments["allowed_types"]?.array ?? []).compactMap(\.string) {
            // "pdf" or ".pdf" is an extension; "public.image" or "com.adobe.pdf" is a type identifier.
            let trimmed = name.hasPrefix(".") ? String(name.dropFirst()) : name
            guard let type = HostPlatform.fileType(named: trimmed) else {
                throw MCPToolError("unknown file type '\(name)'; give an extension such as \"pdf\" or a type identifier such as \"public.image\"")
            }
            types.append(type)
        }
        allowedTypes = types
        if let path = arguments["directory"]?.string {
            guard path.hasPrefix("/"), HostSupport.isFolder(atPath: path) == true else {
                throw MCPToolError("'directory' must be the absolute path of an existing folder: \(path)")
            }
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = nil
        }
    }
}

/// What the cancellation handler needs to close the panel, once it is shown.
@MainActor
private final class PanelBox {
    var cancelPanel: (@MainActor () -> Void)?
    var timedOut = false
    var cancelled = false
}

extension WindowHost {
    /// Shows the panel and waits for the user. Returns {action, paths}.
    nonisolated func pickPath(_ spec: PanelSpec, timeout: Double) async -> JSONValue {
        let box = await MainActor.run { PanelBox() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    if box.cancelled {
                        continuation.resume(returning: ["action": "cancel", "paths": []])
                        return
                    }
                    self.openPanels += 1
                    self.updatePresence()
                    let timeoutTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        box.timedOut = true
                        box.cancelPanel?()
                    }
                    box.cancelPanel = self.platform.beginPanel(spec) { paths in
                        timeoutTask.cancel()
                        self.openPanels -= 1
                        self.updatePresence()
                        guard let paths else {
                            continuation.resume(returning: ["action": box.timedOut ? "timeout" : "cancel", "paths": []])
                            return
                        }
                        continuation.resume(returning: ["action": "accept",
                                                        "paths": .array(paths.map { .string($0) })])
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                box.cancelled = true
                box.cancelPanel?()
            }
        }
    }
}
