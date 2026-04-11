// Helpers/DropHelper.swift
//
// DropModifierView: wraps a content view with SwiftUI .onDrop, bridging the
// isTargeted Binding and async item extraction into ActionUI's actionHandler model.

import SwiftUI
import UniformTypeIdentifiers

/// Wraps a view with `.onDrop(of:isTargeted:perform:)`.
///
/// A wrapper view is required (rather than an inline modifier in `applyModifiers`) because
/// the `isTargeted` binding requires `@State`, which must live in a SwiftUI View struct.
@MainActor
struct DropModifierView<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let onDropActionID: String
    let onDropTypes: [String]
    let onDropTargetedActionID: String?
    let windowUUID: String
    let elementID: Int

    @State private var isTargeted: Bool = false

    var body: some SwiftUI.View {
        let utTypes = onDropTypes.compactMap { UTType($0) }

        // Use a custom binding so that setter fires onDropTargetedActionID
        // without needing .onChange (avoids cross-version API differences).
        let targetedBinding = Binding<Bool>(
            get: { isTargeted },
            set: { newValue in
                isTargeted = newValue
                guard let actionID = onDropTargetedActionID else { return }
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(
                        actionID,
                        windowUUID: windowUUID,
                        viewID: elementID,
                        viewPartID: 0,
                        context: ["isTargeted": newValue]
                    )
                }
            }
        )

        return content
            .onDrop(of: utTypes, isTargeted: targetedBinding) { providers, location in
                let actionID = onDropActionID
                let wUUID = windowUUID
                let eID = elementID
                let loc: [String: Double] = [
                    "x": Double(location.x),
                    "y": Double(location.y)
                ]
                Task { @MainActor in
                    var items: [String] = []
                    for provider in providers {
                        if let text = await Self.loadText(from: provider) {
                            items.append(text)
                        }
                    }
                    ActionUIModel.shared.actionHandler(
                        actionID,
                        windowUUID: wUUID,
                        viewID: eID,
                        viewPartID: 0,
                        context: ["items": items, "location": loc]
                    )
                }
                return true
            }
    }

    /// Attempts to extract a string representation from an NSItemProvider.
    /// Priority order: utf8PlainText → plainText → fileURL (path string).
    /// Returns nil if no supported type is available.
    private static func loadText(from provider: NSItemProvider) async -> String? {
        // Plain text types
        let textTypeIDs = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier
        ]
        for typeID in textTypeIDs {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }
            return await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                    continuation.resume(returning: data.flatMap { String(data: $0, encoding: .utf8) })
                }
            }
        }

        // File / folder URL.
        // macOS returns the URL in one of several ways depending on the source and OS version:
        //   • loadDataRepresentation → Data containing a UTF-8 "file://…" URL string
        //   • loadItem              → NSURL / URL object, or Data with the UTF-8 URL string
        // We try both paths and return whichever succeeds first.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            // Path 1: loadDataRepresentation (most reliable on macOS Finder drags)
            let viaData: String? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data else { continuation.resume(returning: nil); return }
                    let urlString = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: urlString.flatMap { URL(string: $0)?.path } ?? urlString)
                }
            }
            if let result = viaData, !result.isEmpty { return result }

            // Path 2: loadItem (returns NSURL on some systems, Data on others)
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    switch item {
                    case let url as URL:
                        continuation.resume(returning: url.path)
                    case let nsurl as NSURL:
                        continuation.resume(returning: nsurl.path)
                    case let data as Data:
                        let str = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: str.flatMap { URL(string: $0)?.path } ?? str)
                    case let str as String:
                        continuation.resume(returning: URL(string: str)?.path ?? str)
                    default:
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }
}
