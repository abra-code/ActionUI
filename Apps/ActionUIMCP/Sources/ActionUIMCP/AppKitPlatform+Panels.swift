// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform+Panels.swift - NSOpenPanel and NSSavePanel, run with begin(completionHandler:), not
// runModal, so the main run loop keeps serving other tool calls.

#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

extension AppKitPlatform {
    nonisolated static func fileType(named name: String) -> UTType? {
        name.contains(".") ? UTType(name) : UTType(filenameExtension: name)
    }

    func beginPanel(_ spec: PanelSpec, completion: @escaping @MainActor ([String]?) -> Void) -> @MainActor () -> Void {
        let panel = makePanel(spec)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else {
                completion(nil)
                return
            }
            let urls = (panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? []
            completion(urls.map(\.path))
        }
        return { panel.cancel(nil) }
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
#endif
