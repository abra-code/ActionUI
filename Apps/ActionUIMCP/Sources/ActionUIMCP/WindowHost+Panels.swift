// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost+Panels.swift - pick_path: the system open and save panels. A panel runs free-standing
// (begin(completionHandler:), not runModal), so the main run loop keeps serving other tool calls
// while the user browses.

import AppKit
import UniformTypeIdentifiers
import MCPStdio

struct PanelSpec {
    enum Kind: String, CaseIterable { case file, folder, save }

    let kind: Kind
    let title: String?
    let message: String?
    let allowedTypes: [UTType]
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
        var types: [UTType] = []
        for name in (arguments["allowed_types"]?.array ?? []).compactMap(\.string) {
            // "pdf" or ".pdf" is an extension; "public.image" or "com.adobe.pdf" is a type identifier.
            let trimmed = name.hasPrefix(".") ? String(name.dropFirst()) : name
            guard let type = trimmed.contains(".") ? UTType(trimmed) : UTType(filenameExtension: trimmed) else {
                throw MCPToolError("unknown file type '\(name)'; give an extension such as \"pdf\" or a type identifier such as \"public.image\"")
            }
            types.append(type)
        }
        allowedTypes = types
        if let path = arguments["directory"]?.string {
            var isDirectory: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw MCPToolError("'directory' must be the absolute path of an existing folder: \(path)")
            }
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = nil
        }
    }
}

/// The panel, once shown, so the cancellation handler can close it.
@MainActor
private final class PanelBox {
    var panel: NSSavePanel?
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
                    let panel = self.makePanel(spec)
                    box.panel = panel
                    self.openPanels += 1
                    self.updateActivationPolicy()
                    let timeoutTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        box.timedOut = true
                        panel.cancel(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                    panel.begin { response in
                        timeoutTask.cancel()
                        self.openPanels -= 1
                        self.updateActivationPolicy()
                        guard response == .OK else {
                            continuation.resume(returning: ["action": box.timedOut ? "timeout" : "cancel", "paths": []])
                            return
                        }
                        let urls = (panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? []
                        continuation.resume(returning: ["action": "accept",
                                                        "paths": .array(urls.map { .string($0.path) })])
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                box.cancelled = true
                box.panel?.cancel(nil)
            }
        }
    }

    private func makePanel(_ spec: PanelSpec) -> NSSavePanel {
        let panel: NSSavePanel
        switch spec.kind {
        case .save:
            panel = NSSavePanel()
            panel.canCreateDirectories = true
            if let name = spec.defaultName { panel.nameFieldStringValue = name }
        case .file, .folder:
            let open = NSOpenPanel()
            open.canChooseFiles = spec.kind == .file
            open.canChooseDirectories = spec.kind == .folder
            open.allowsMultipleSelection = spec.multiple
            open.canCreateDirectories = spec.kind == .folder
            panel = open
        }
        if !spec.allowedTypes.isEmpty && spec.kind != .folder { panel.allowedContentTypes = spec.allowedTypes }
        if let title = spec.title { panel.title = title }
        if let message = spec.message { panel.message = message }
        if let directory = spec.directory { panel.directoryURL = directory }
        return panel
    }
}
